#!/bin/bash
########################################################################
#
# README
#
########################################################################
#
# This is a basic blog generator
#
# Program execution starts at the end of this file, after the final
# function declaration.
#
# todo: add more information here
#
########################################################################
#
# LICENSE
#
########################################################################
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# location of config file
# values found in here overload defaults in this script
# expected format:
# key="value"
global_config="bashblog.conf"
# log file defined outside of initializeGlobalVariables
# b/c logging starts before it would be defined!
global_logFile="bashblog.log"
# these are needed in order to exit entire script
# even when inside a subshell. ex: $(parse ......)
PID=$$
trap "builtin exit" TERM

# run at beginning of script to generate globals
#
# takes no args
initializeGlobalVariables() {
    log "[Info] Loading default globals"

    global_softwareName="BashBlog"
    global_softwareVersion="1.0.1"

    global_title="My blog" # blog title
    global_description="Blogger blogging on my blog" # blog subtitle
    global_url="http://example.com/blog" # top-level URL for accessing blog
    global_author="John Doe" # your name
    global_authorUrl="$global_url" # optional link to a a facebook profile, etc.
    global_email="johndoe@example.com" # your email
    global_license="CC by-nc-nd" # "&copy;" for copyright, for example

    global_sourceDir="source" # dir for easy-to-edit source             # best
    global_draftsDir="drafts" # dir for drafts                          # to leave
    global_htmlDir="html" # dir for final html files                    # these
    global_tempDir="/tmp/$global_softwareName" # dir for pending files  # alone

    global_indexFile="index.html" # index page, best to leave alone
    global_archiveFile="archive.html" # page to list all posts, best to leave alone
    global_headerFile=".header.html" # header file
    global_footerFile=".footer.html" # footer file
    global_blogcssFile="blog.css" # blog's styling, is put in global_htmlDir

    global_feed="feed.rss" # rss feed file
    global_feedLength="10" # num of articles to include in feed

    global_syncFunction="" # example: "cp -r ./$global_htmlDir /mnt/backup/blog/"

    global_backupFile="backup.tar.gz" # destination for backup

    niceDateFormat="%B %d, %Y" # for displaying, not timestamps
    markdownBinary="$(which Markdown.pl)"
}

# makes sure markdown is working correctly
# ex usage:
# [[ testMarkdown -ne 0 ]] && echo "bad markdown" && return 1
#
# takes no args
testMarkdown() {
    [[ -z "$markdownBinary" ]] && return 1
    [[ -z "$(which diff)" ]] && return 1

    local in="/tmp/md-in-$(echo $RANDOM).md"
    local out="/tmp/md-out-$(echo $RANDOM).html"
    local good="/tmp/md-good-$(echo $RANDOM).html"
    echo -e "line 1\n\nline 2" > $in
    echo -e "<p>line 1</p>\n\n<p>line 2</p>" > $good
    $markdownBinary $in > $out 2> /dev/null
    diff $good $out &> /dev/null # output is irrelevant, check $?
    if [[ $? -ne 0 ]]; then
        rm -f $in $good $out
        return 1
    fi
    rm -f $in $good $out
    return 0
}

# Detects if GNU date is installed
#
# takes no args
detectDateVersion() {
    date --version >/dev/null 2>&1
    if [[ $? -ne 0 ]];  then
        # date utility is BSD. Test if gdate is installed
        if gdate --version >/dev/null 2>&1 ; then
            date() {
                gdate "$@"
            }
        else
            # BSD date
            date() {
                if [[ "$1" == "-r" ]]; then
                    # Fall back to using stat for 'date -r'
                    local format=$(echo $3 | sed 's/\+//g')
                    local stat -f "%Sm" -t "$format" "$2"
                elif [[ $(echo $@ | grep '\-\-date') ]]; then
                    # convert between dates using BSD date syntax
                    /bin/date -j -f "%a, %d %b %Y %H:%M:%S %z" "$(echo $2 | sed 's/\-\-date\=//g')" "$1"
                else
                    # acceptable format for BSD date
                    /bin/date -j "$@"
                fi
            }
        fi
    fi
}

# echo usage info at the user
#
# takes no args
usage() {
    echo $global_softwareName v$global_softwareVersion
    echo "Usage: $0 command"
    echo "<required> [optional]"
    echo "Commands:"
    echo "    edit <filename> .............. edit a file and republish if necessary"
    echo "    post [markdown] [filename] ... publish a blog entry"
    echo "                                   if markdown not specified, then assume html"
    echo "                                   if no filename, start from scratch"
    echo "    rebuild ...................... start rebuild process: can regenerate index,"
    echo "                                   css, etc. from scratch"
    echo "                                   useful when you've changed a global variable"
    echo "    reset ........................ delete basically everything to start fresh"
    echo ""
    echo "For more information, see README and $0 in a text editor"
    log "[Info] Showing usage"
}

# fills a pending post with template
#
# $1    format, "md" or "html"
# $2    filename
fillPostTemplate() {
    log "[Info] Applying template to $2"
    local date=$(date +'%Y%m%d')
    local datetime=$(date +'%Y%m%d%H%M%S')
    if [[ $1 == "md" ]]; then local content="This is the body of your post. You may format with **markdown**.\n\nUse as many lines as you wish.";
    else local content="<p>This is the body of your post. You may format with <b>html</b></p>\n\n<p>Use as many lines as you wish.</p>"; fi
    echo "---------DO-NOT-EDIT-THIS-SECTION----------"  > $2
    echo $1                                            >> $2 # format
    echo $date                                         >> $2 # original datetime
    echo $datetime                                     >> $2 # edit datetime
    echo "----------------POST-CONTENT---------------" >> $2
    echo "Title goes on this line"                     >> $2
    echo "-------------------------------------------" >> $2
    echo -e $content                                   >> $2
    echo "---------POST-TAGS---ONE-PER-LINE----------" >> $2
    echo ""                                            >> $2
}

# performs the sync function (if any)
# and logs about it
#
# takes no args
sync() {
    if [[ ! -z "$global_syncFunction" ]]; then
        echo "Starting sync"
        log "[Info] Starting sync"
        $global_syncFunction
        echo "End of sync"
        log "[Info] End of sync"
    else
        log "[Info] No sync function"
    fi

}

# fetches desired info from passed filename
#
# $1    label for desired info: "format", "postDate", "editDate", "title", "tags"
# $2    filename to get the info from
getFromSource() {
    while read line # gets line 1
    do
        read line # gets line 2
        if [[ "$1" == "format" ]]; then
            echo "$line"
            break
        fi
        read line # gets line 3
        if [[ "$1" == "postDate" ]]; then
            echo "$line"
            break
        fi
        read line # gets line 4
        if [[ "$1" == "editDate" ]]; then
            echo "$line"
            break
        fi
        read line # gets line 5
        read line # gets line 6
        if [[ "$1" == "title" ]]; then
            echo "$line"
            break
        fi
        if [[ "$1" == "tags" ]]; then
            local foundTags="false"
            local tags
            while read line # loop through the remaining lines
            do
                # this line should be executed everytime after tags are found
                [[ $foundTags == "true" ]] && tags="$tags;$line" && continue
                # this line basically makes sure we are at the tags and then puts the first one in the tags variable
                [[ "$line" == "---------POST-TAGS---ONE-PER-LINE----------" ]] && foundTags="true" && read line && tags="$line"
            done
            echo "$tags"
            break
        fi
        break
    done < "$2"
}

# changes a value in the passed source file
# does not sync to a published file!
#
# $1    label for desired info to set: "format", "postDate", "editDate", "title"
# $2    value to change to
# $3    filename to set info in
setInSource() {
    while read line # get line 1
    do
        read line # get line 2
        if [[ "$1" == "format" ]]; then
            local replacement="0,/$line/{s/$line/$2/}"
            sed -i "$replacement" "$3"
            break
        fi
        read line # get line 3
        if [[ "$1" == "postDate" ]]; then
            local replacement="0,/$line/{s/$line/$2/}"
            sed -i "$replacement" "$3"
            break
        fi
        read line # get line 4
        if [[ "$1" == "editDate" ]]; then
            local replacement="0,/$line/{s/$line/$2/}"
            sed -i "$replacement" "$3"
            break
        fi
        read line # get line 5
        read line # get line 6
        if [[ "$1" == "title" ]]; then
            local replacement="0,/$line/{s/$line/$2/}"
            sed -i "$replacement" "$3"
            break
        fi
        break
    done < "$3"
}

# edit a file and start the process of republishing if needed
# got here with "./bashblog2.sh edit filename"
#
# $1    filename to edit
edit() {
    if [[ "$1" == *$global_sourceDir/* ]]; then
        # tell blogger that the edit date will be changed automatically
        setInSource "editDate" "edit-date: auto changes after edit" "$1"
        # tell blogger that he can't change the title
        local title=$(getFromSource "title" "$1")
        setInSource "title" "Can't change title: $title" "$1"
        # do actual editing
        log "[Info] Entering editor $EDITOR"
        $EDITOR "$1"
        log "[Info] Exited editor $EDITOR"
        # set edit date in file
        setInSource "editDate" "$(date +'%Y%m%d%H%M%S')" "$1"
        # set title back to original title
        setInSource "title" "$title" "$1"
        # republish it
        local publishedFile=$(parse "$1" "$global_htmlDir" $global_htmlDir/$(echo $(basename "$1") | sed 's/html$\|md$/html/'))
        echo "Republished as "$(basename $publishedFile)
        log "[Info] Republished $publishedFile"
        buildIndex
        buildArchive
        buildFeed
        sync
    elif [[ "$1" == *$global_draftsDir/* ]]; then
        # use post func to edit and possibly publish
        post $(getFromSource "format" "$1") "$1"
        # don't need to sync, post func does it for us
    else
        # warn that this will only edit an arbitrary file and run sync func
        echo "You are going to edit a file outside of $global_draftsDir and $global_sourceDir."
        echo "You can do that, and I'll run the sync function (if any), but that's it."
        echo -n "Are you sure you want to continue? (y/N) ";
        read response && echo
        response=$(echo $response | tr '[:upper:]' '[:lower:]')
        if [[ "$response" == "y" ]]; then
            log "[Info] Entering editor $EDITOR"
            $EDITOR "$1"
            log "[Info] Exited editor $EDITOR"
            #buildIndex
            #buildArchive
            #buildFeed
            sync
        fi
    fi
}

# parse the given file into html
# and put it all into the given filename
#
# $1    file to parse
# $2    dir to put parsed .html file into
# $3    overwriteFile, not empty if want to ignore filename conflicts. Contains name of file to overwrite
# returns $2/title-of-post.html
parse() {
    local format
    local postDate
    local editDate
    local title
    local content
    local tags
    local filename
    local onTags="false"
    local overwriteFile="$3"
    local line
    local OIFS=$IFS
    IFS=
    while read -r line; do
        if [[ "$line" == "---------DO-NOT-EDIT-THIS-SECTION----------" ]]; then
            read line # format content is in, "md" or "html"
            if [[ -z "$format" ]]; then
                format="$line"
                if [[ $format != "md" ]] && [[ $format != "html" ]]; then
                    exit "[Error] Couldn't parse file: invalid format" "Couldn't parse file: invalid format"
                fi
            fi
            read line # posting date, should never change
            if [[ -z "$postDate" ]]; then
                postDate="$line"
                if [[ ! $postDate =~ ^[0-9]+$ ]]; then
                    exit "[Error] Couldn't parse file: invalid post date" "Couldn't parse file: invalid date"
                fi
            fi
            read line # edit date, changes when editing after publication
            if [[ -z "$editDate" ]]; then
                editDate="$line"
                if [[ ! $editDate =~ ^[0-9]+$ ]]; then
                    exit "[Error] Couldn't parse file: invalid edit date" "Couldn't parse file: invalid date"
                fi
            fi
        elif [[ "$line" == "----------------POST-CONTENT---------------" ]]; then
            read line # title, then also convert into filename
            title="$line"
            # get filename based on title: all lower case, spaces to dashes, all alphanumeric
            filename="$2/$(echo $title | tr [:upper:] [:lower:] | sed 's/\ /-/g' | tr -dc '[:alnum:]-').html"
            # if wanting to overwrite
            read line # spacer between title and content
        elif [[ "$line" != "---------POST-TAGS---ONE-PER-LINE----------" ]] && [[ $onTags == "false" ]]; then
            # get everything before tag divider into the content variable
            [[ ! -z "$content" ]] && content="$content\n$line" || content="$line"
        else
            onTags="true"
            # get tags, except first thing will be the divider so continue first
            [[ "$line" == "---------POST-TAGS---ONE-PER-LINE----------" ]] && continue
            if [[ $line =~ ^.*\;.*$ ]]; then
                exit "[Error] Couldn't parse file: bad tags" "Coudln't parse file: tags can't have \";\" in them"
            else
                # append latest tag to list, dividing each with ";"
                [[ ! -z "$tags" ]] && tags="$tags;$line" || tags="$line"
            fi
        fi
    done < "$1"
    IFS=$OIFS
    # make sure filename is unique if no overwriteFile specified
    while [[ -f "$filename" ]] && [[ -z "$overwriteFile" ]]; do
        filename=$(echo $filename | sed 's/\.html$//')"-$RANDOM.html"
    done
    if [[ ! -z "$overwriteFile" ]]; then
        filename="$overwriteFile"
    fi
    createHtmlPage $format $postDate $editDate "$title" "$content" "$tags" "$filename"
}

# takes parsed information
# and turns into an html file
# ready for publishing (or previewing)
#
# $1    format, "md" or "html"
# $2    date & time of original posting
# $3    date & time of latest edit
# $4    title of post (or blog if index or archive)
# $5    content of post
# $6    tags of post, if any
# $7    filename where everything goes
# returns $7
createHtmlPage() {
    local format=$1
    local postDate=$2;# postDate="${postDate:0:8} ${postDate:8:2}:${postDate:10:2}:${postDate:12:2}"
    local editDate=$3; editDate="${editDate:0:8} ${editDate:8:2}:${editDate:10:2}:${editDate:12:2}"
    local title="$4"
    local content="$5"; [[ $format == "md" ]] && content=$(markdown "$content")
    local tagList="$6"
    local filename="$7"

    cat "$global_headerFile" > "$filename"
    echo "<title>$title</title>" >> "$filename"
    echo "</head><body>" >> "$filename"
    # body divs
    echo '<div id="divbodyholder">' >> "$filename"
    echo '<div class="headerholder"><div class="header">' >> "$filename"
    # blog title
    echo '<div id="title"><h1 class="nomargin"><a class="ablack" href="'$global_url'">'$global_title'</a></h1>' >> "$filename"
    echo '<div id="description">'$global_description'</div>' >> "$filename"
    # title, header, headerholder respectively
    echo '</div></div></div>' >> "$filename"
    echo '<div id="divbody"><div class="content">' >> "$filename"

    # not doing index or archive, just one entry
    if [[ "$filename" != "$global_htmlDir/$global_indexFile" ]] && [[ "$filename" != "$global_htmlDir/$global_archiveFile" ]]; then
        echo '<!-- entry begin -->' >> "$filename" # marks the beginning of the whole post
        echo '<h3><a class="ablack" href="'$global_url"$(echo $filename | sed "s/$global_htmlDir//")"'">' >> "$filename"
        # remove possible <p>'s on the title because of markdown conversion
        echo "$(echo "$title" | sed 's/<\/*p>//g')" >> "$filename"
        echo '</a></h3>' >> "$filename"
        echo '<div class="subtitle">'$(date +"$niceDateFormat" --date="$postDate") ' &mdash; ' >> "$filename"
        echo "$global_author" >> "$filename"
        [[ ! -z "$tagList" ]] && echo "<br>Tags: <code>"$(echo $tagList | sed 's/;/<\/code>, <code>/g')"</code></div>" >> "$filename" || echo "</div>" >> "$filename"
        echo '<!-- text begin -->' >> "$filename" # This marks the beginning of the actual content
    fi
    echo -e "$content" >> "$filename" # body of post finally
    # not doing index, just one entry
    if [[ "$filename" != "$global_htmlDir/$global_indexFile" ]] && [[ "$filename" != "$global_htmlDir/$global_archiveFile" ]]; then
        echo '<!-- text end -->' >> "$filename"
        echo '<!-- entry end -->' >> "$filename" # end of post
    fi
    echo '</div>' >> "$filename" # content
    cat "$global_footerFile" >> "$filename"
    echo '</body></html>' >> "$filename"

    echo $7
}

# generates $global_feed file
#
# takes no args
buildFeed() {
	log "[Info] Starting build of $global_feed"
	local feedFile="$global_htmlDir/$global_feed"
	echo '<?xml version="1.0" encoding="UTF-8" ?>' > "$feedFile"
    echo '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">' >> "$feedFile"
    echo '<channel><title>'$global_title'</title><link>'$global_url'</link>' >> "$feedFile"
    echo '<description>'$global_description'</description><language>en</language>' >> "$feedFile"
    echo '<lastBuildDate>'$(date +"%a, %d %b %Y %H:%M:%S %z")'</lastBuildDate>' >> "$feedFile"
    echo '<pubDate>'$(date +"%a, %d %b %Y %H:%M:%S %z")'</pubDate>' >> "$feedFile"
    echo '<atom:link href="'$global_url/$global_feed'" rel="self" type="application/rss+xml" />' >> "$feedFile"
    # See buildIndex and buildArchive for details on the sorting process....
    local postList=$(find "$global_sourceDir" -type f | grep '.html\|.md')
    local unsortedList
	local n=0
	while [[ n -lt $global_feedLength ]] && read line
    do
        if [[ "$line" == "$global_htmlDir/$global_indexFile" ]] || [[ "$line" == "$global_htmlDir/$global_archiveFile" ]]; then
            continue
        fi
        unsortedList="$unsortedList"$(echo $(getFromSource "postDate" "$line") "$line")"\n"
        n=$(($n+1));
    done <<< "$postList"
    local sortedList=$(echo -e $unsortedList | sort -r)
    for sortedFile in $(echo "$sortedList" | sed 's/[0-9]*\ //')
    do
		local publishedFile="$global_htmlDir/"$(echo $(basename "$sortedFile") | sed 's/html$\|md$/html/')
        echo '<item>' >> "$feedFile"
        echo -n '<title>' >> "$feedFile"
        # maybe I should just get the title from source??? Side effect of using old code
        echo -n "$(awk '/<h3><a class="ablack" href=".+">/, /<\/a><\/h3>/{if (!/<h3><a class="ablack" href=".+">/ && !/<\/a><\/h3>/) print}' $publishedFile)" >> "$feedFile"
        echo '</title>' >> "$feedFile"
        echo '<description><![CDATA[' >> "$feedFile"
        echo "$(awk '/<!-- text begin -->/, /<!-- text end -->/{if (!/<!-- text begin -->/ && !/<!-- text end -->/) print}' $publishedFile)" >> "$feedFile"
        echo "]]></description>" >> "$feedFile"
        echo "<link>$global_url/"$(basename "$publishedFile")"</link>" >> "$feedFile"
        echo "<guid>$global_url/"$(basename "$publishedFile")"</guid>" >> "$feedFile"
        echo "<dc:creator>$global_author</dc:creator>" >> "$feedFile"
        # hey, I'm getting the publication date from source!
        echo '<pubDate>'$(date +"%a, %d %b %Y %H:%M:%S %z" --date=$(getFromSource "postDate" "$sortedFile"))'</pubDate>' >> "$feedFile"
        echo '</item>' >> "$feedFile"
    done
    echo '</channel></rss>' >> "$feedFile"

    echo "Built $feedFile"
    log "[Info] Done building "$(basename "$feedFile")
}

# generate $global_indexFile again,
# containing up to the last ten posts' contents
#
# takes no args
buildIndex() {
    log "[Info] Starting build of $global_indexFile"
    local content
    # get list of files in source dir that should have the file names
    # (except extensions) of all published posts
    local postList=$(find "$global_sourceDir" -type f | grep '.html\|.md')
    local unsortedList
    local n=0
    while [[ n -lt $global_feedLength ]] && read line
    do
        # I'm pretty sure this will never happen as posts are being searched for in the source dir
        if [[ "$line" == "$global_htmlDir/$global_indexFile" ]] || [[ "$line" == "$global_htmlDir/$global_archiveFile" ]]; then
            continue
        fi
        # append to unsorted list in the following format
        # "date" "filename"
        # 20141231 source/title-of-post.md
        unsortedList="$unsortedList"$(echo $(getFromSource "postDate" "$line") "$line")"\n"
        n=$(($n+1));
    done <<< "$postList"
    local sortedList=$(echo -e $unsortedList | sort -r) # sort by date using sort command
    for sortedFile in $(echo "$sortedList" | sed 's/[0-9]*\ //') # get each file name out of sorted list
    do
        local publishedFile="$global_htmlDir/"$(echo $(basename "$sortedFile") | sed 's/html$\|md$/html/') # remove "source/" and set extension to ".html"
        content="$content\n"$(awk '/<!-- entry begin -->/, /<!-- entry end -->/' "$publishedFile")
    done
    content=$content'\n<div id="all_posts"><a href="'$global_url'/'$global_archiveFile'">See all posts</a></div>'
    echo "Built "$(createHtmlPage "" "" "" "$global_title" "$content" "" "$global_htmlDir/$global_indexFile")
    log "[Info] Done building $global_indexFile"
}

# generate $global_archiveFile again,
# containing links to all posts ever made
#
# takes no args
buildArchive() {
    log "[Info] Starting build of $global_archiveFile"
    local content="<h3>All posts</h3>"
    content="$content\n<ul>"


    # get list of files in source dir that should have the file names
    # (except extensions) of all published posts
    local postList=$(find "$global_sourceDir" -type f | grep '.html\|.md')
    local unsortedList
    while read line
    do
        # skip index or archive if found for some stupid reason. This should never happen. Probably should be taken out
        if [[ "$line" == "$global_htmlDir/$global_indexFile" ]] || [[ "$line" == "$global_htmlDir/$global_archiveFile" ]]; then
            continue
        fi
        # append to unsorted list in the following format
        # "date" "filename"
        # 20141231 source/title-of-post.md
        unsortedList="$unsortedList"$(echo $(getFromSource "postDate" "$line") "$line")"\n"
        n=$(($n+1));
    done <<< "$postList"
    # use sort command to sort list by date
    # note: date resolution only to the day. Multiple posts per day are sorted in reverse alphabetical I think
    local sortedList=$(echo -e $unsortedList | sort -r)
    for sortedFile in $(echo "$sortedList" | sed 's/[0-9]*\ //') # get each file name out of sorted list
    do
        local title=$(getFromSource "title" "$sortedFile")
        local postDate=$(date +"$niceDateFormat" --date="$(getFromSource "postDate" "$sortedFile")")
        local tagList=$(getFromSource "tags" "$sortedFile")
        local fileName=$(echo $(basename "$sortedFile") | sed 's/html$\|md$/html/') # remove "source/" and make sure extension is ".html"
        content=$content'\n<li><a href="'$global_url/$fileName'">'$title'</a> &mdash; '$postDate'<br>'
        if [[ "$tagList" =~ [:alnum:]+ ]]; then
            content=$content'<pre>    Tags: <code>'$(echo $tagList | sed 's/;/<\/code>, <code>/g')'</code></pre></li>'
        fi
    done
    content="$content\n</ul>"
    content=$content'\n<div id="all_posts"><a href="'$global_url'">Back to index</a></div>'

    echo "Built "$(createHtmlPage "" "" "" "$global_title" "$content" "" "$global_htmlDir/$global_archiveFile")
    log "[Info] Done building $global_archiveFile"
}

# publish a file
# got here with "./bashblog2.sh post [filename]"
#
# $1    format, "md" or "html"
# $2    filename, optional
post() {
    local format=$1
    local filename="$2"
    # if no filename passed, posting a new file. Make a temp file
    if [[ -z "$filename" ]]; then
        filename="$global_tempDir/$RANDOM$RANDOM$RANDOM"
        fillPostTemplate $format $filename
    fi
    # do any editing if the blogger wants to
    local postResponse="e"
    while [[ "$postResponse" != "p" ]] && [[ "$postResponse" != "d" ]] && [[ "$postResponse" != "q" ]]
    do
        $EDITOR "$filename"
        # see if blogger wants to preview post
        local previewResponse="n"
        echo -n "Preview post? (y/N) "
        read previewResponse && echo
        previewResponse=$(echo $previewResponse | tr '[:upper:]' '[:lower:]')
        if [[ "$previewResponse" == "y" ]]; then
            # yes he does
            local dashedTitle=$(echo $(getFromSource "title" "$filename") | tr [:upper:] [:lower:] | sed 's/\ /-/g' | tr -dc '[:alnum:]-')
            local parsedPreview="$(parse "$filename" "$global_htmlDir/preview" "$global_htmlDir/preview/$dashedTitle")" # filename of where preview is on disk
            local url=$global_url"$(echo $parsedPreview | sed "s/$global_htmlDir//")" # url of preview, assuming sync is set up
            log "[Info] Generating preview $parsedPreview"
            sync
            echo "See $parsedPreview"
            echo "or $url"
            echo "depending on your configuration"
        else
            # do nothing
            echo "" &> /dev/null
        fi

        echo -n "[P]ublish, [E]dit, [D]raft for later, [Q]uit? (p/E/d/q) "
        read postResponse && echo
        postResponse=$(echo $postResponse | tr '[:upper:]' '[:lower:]')
    done
    # don't know if blogger previewed, so just delete any preview
    [[ -f "$parsedPreview" ]] && rm "$parsedPreview" && log "[Info] Deleted $parsedPreview"
    if [[ "$postResponse" == "p" ]]; then
        # parse directly into htmldir
        local parsedPost="$(parse "$filename" "$global_htmlDir")"
        # move source from tempdir to sourcedir, renaming to nice name
        mv "$filename" "$global_sourceDir/"$(basename $parsedPost .html)".$format"
        # echo/log afterwards because need title of post in echo/log
        echo "Publishing "$(basename $parsedPost)
        log "[Info] Publishing $parsedPost"
        buildIndex
        buildArchive
        buildFeed
        sync
    elif [[ "$postResponse" == "d" ]]; then
        local dashedTitle=$(echo $(getFromSource "title" "$filename") | tr [:upper:] [:lower:] | sed 's/\ /-/g' | tr -dc '[:alnum:]-')
        echo "Saving $global_draftsDir/$dashedTitle.$format"
        log "[Info] Saving $global_draftsDir/$dashedTitle.$format"
        mv "$filename" "$global_draftsDir/$dashedTitle.$format" &> /dev/null
        sync
    elif [[ "$postResponse" == "q" ]]; then
        log "[Info] Post process halted"
    fi


}

# backup desired files to compressed tarball
# best to leave $global_backupList alone
#
# takes no args
backup() {
    local backupList="$global_sourceDir $global_draftsDir $global_htmlDir $global_config"
    tar cfz $global_backupFile $backupList &> /dev/null
    [[ $? -ne 0 ]] && log "[Warning] Backup error" || log "[Info] Backup success"
    chmod 600 $global_backupFile
}

# takes markdown-formatted string and
# returns html-formatted string
#
# $1 markdown-formatted string
markdown() {
    log "[Info] Translating markdown"
    echo -e "$1" | $markdownBinary
}

# if the file does not already exist,
# creates style sheet from scratch
#
# $1    if anything, then force overwrite
createCss() {
    # this is basically a line-for-line copy of the original bashblog's css
    # if you're comparing it to the original, this is the css for
    # both the blog.css and main.css files. Some things may not be relevant anymore,
    # or may be ready to style things that haven't been implemented yet in bashblog2.
    #
    # This needs to be reviewed.
    if [[ ! -f "$global_htmlDir/$global_blogcssFile" ]] || [[ ! -z "$1" ]]; then
    [[ ! -f "$global_htmlDir/$global_blogcssFile" ]] && log "[Warning] blog.css file not found."
    log "[Info] Regenerating blog.css from scratch"
    echo 'body{font-family:Georgia,"Times New Roman",Times,serif;margin:0;padding:0;background-color:#F3F3F3;}
#divbodyholder{padding:5px;background-color:#DDD;width:874px;margin:24px auto;}
#divbody{width:776px;border:solid 1px #ccc;background-color:#fff;padding:0px 48px 24px 48px;top:0;}
.headerholder{background-color:#f9f9f9;border-top:solid 1px #ccc;border-left:solid 1px #ccc;border-right:solid 1px #ccc;}
.header{width:800px;margin:0px auto;padding-top:24px;padding-bottom:8px;}
.content{margin-bottom:45px;}
.nomargin{margin:0;}
.description{margin-top:10px;border-top:solid 1px #666;padding:10px 0;}
h3{font-size:20pt;width:100%;font-weight:bold;margin-top:32px;margin-bottom:0;}
.clear{clear:both;}
#footer{padding-top:10px;border-top:solid 1px #666;color:#333333;text-align:center;font-size:small;font-family:"Courier New","Courier",monospace;}
a{text-decoration:none;color:#003366 !important;}
a:visited{text-decoration:none;color:#336699 !important;}
blockquote{background-color:#f9f9f9;border-left:solid 4px #e9e9e9;margin-left:12px;padding:12px 12px 12px 24px;}
blockquote img{margin:12px 0px;}
blockquote iframe{margin:12px 0px;}
#title{font-size: x-large;}
a.ablack{color:black !important;}
li{margin-bottom:8px;}
ul,ol{margin-left:24px;margin-right:24px;}
#all_posts{margin-top:24px;text-align:center;}
.subtitle{font-size:small;margin:12px 0px;}
.content p{margin-left:24px;margin-right:24px;}
h1{margin-bottom:12px !important;}
#description{font-size:large;margin-bottom:12px;}
h3{margin-top:42px;margin-bottom:8px;}
h4{margin-left:24px;margin-right:24px;}
#twitter{line-height:20px;vertical-align:top;text-align:right;font-style:italic;color:#333;margin-top:24px;font-size:14px;}' > "$global_htmlDir/$global_blogcssFile"
    [[ ! -f "$global_htmlDir/preview/$global_blogcssFile" ]] && ln -s "../$global_blogcssFile" "$global_htmlDir/preview/$global_blogcssFile"
    fi
}

# if they do not already exist,
# creates header and footer from scratch
#
# $1    if anything, then force overwrite
createHeaderFooter() {
    if [[ ! -f "$global_headerFile" ]] || [[ ! -z "$1" ]]; then
    [[ ! -f "$global_headerFile" ]] && log "[Warning] Header file not found."
    log "[Info] Regenerating header file."
        echo '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml"><head>
<meta http-equiv="Content-type" content="text/html;charset=UTF-8" />
<link rel="stylesheet" href="'$global_blogcssFile'" type="text/css" />' > "$global_headerFile"
    fi
    if [[ ! -f "$global_footerFile" ]] || [[ ! -z "$1" ]]; then
    [[ ! -f "$global_footerFile" ]] && log "[Warning] Footer file not found."
    log "[Info] Regenerating footer file."
        local protected_mail="$(echo "$global_email" | sed 's/@/\&#64;/g' | sed 's/\./\&#46;/g')"
        echo '<div id="footer">'$global_license '<a href="'$global_author_url'">'$global_author'</a> &mdash; <a href="mailto:'$protected_mail'">'$protected_mail'</a><br/>
Generated with <a href="https://bitbucket.org/pointychimp/bashblog">bashblog</a>, based on <a href="https://github.com/cfenollosa/bashblog">bashblog</a></div>' > "$global_footerFile"
    fi
}

# prepare everything to get ready
# creates css file(s), makes directories,
# get global variables initialized, etc.
#
# takes no args
initialize() {
    log "[Info] Initializing"
    detectDateVersion
    initializeGlobalVariables
    [[ -f "$global_config" ]] && log "[Info] Overloading globals with $global_config" && source "$global_config" &> /dev/null
    mkdir -p "$global_sourceDir" "$global_draftsDir" "$global_htmlDir/preview" "$global_tempDir"
    createCss
    createHeaderFooter
}

# wrapper for logging to $global_logFile
#
# $1    stuff to put in log file
log() {
    echo -n "$(date +"[%Y-%m-%d %H:%M:%S]")" >> $global_logFile
    #echo -n "[$$]" >> $global_logFile
    echo "$1" >> $global_logFile
}

# overload of exit function
#
# $1    optional message to log
# $2    optional message to print (requires $1 to exist)
exit() {
    [[ ! -z "$1" ]] && log "$1"
    [[ ! -z "$2" ]] && echo "$2"
    log "[Info] Ending run"
    kill -s TERM $PID
}

########################################################################
# main (execution starts here)
########################################################################
log "[Info] Starting run"
initialize

# make sure $EDITOR is set
[[ -z $EDITOR ]] && exit "[Error] \$EDITOR not exported" "Set \$EDITOR enviroment variable"
# check for valid arguments
# chain them together like [[  ]] && [[  ]] && ... && usage && exit
[[ $1 != "edit" ]] && [[ $1 != "post" ]] && [[ $1 != "rebuild" ]] && [[ $1 != "reset" ]] && usage && exit

#
# edit option
#############
# $1    "edit"
# $2    filename
if [[ $1 == "edit" ]]; then
    if [[ $# -lt 2 ]]; then
        exit "[Error] No file passed" "Enter a valid file to edit"
    elif [[ ! -f "$2" ]]; then
        exit "[Error] File does not exist" "$2 does not exist"
    else
        backup
        edit "$2" # $2 is a filename
    fi
fi
#############

#
# post option
#############
# $1    "post"
# $2    "markdown" or filename
# $3    if $2=="markdown", $3==filename
if [[ $1 == "post" ]]; then
    format=""
    filename=""

    if [[ $2 == "markdown" ]]; then filename="$3";
    else filename="$2"; fi

    if [[ "$filename" == *$global_sourceDir/* ]]; then
        echo "You can't post something from the $global_sourceDir directory."
        echo "Try $0 edit $filename"
        exit "[Error] Can't post out of $global_sourceDir"
    fi

    if [[ -z "$filename" ]]; then
        # no filename, generate new file
        if [[ $2 == "markdown" ]]; then format="md";
        else format="html"; fi
        backup
        log "[Info] Going to post a new $format file"
        post $format
    elif [[ -f "$filename" ]]; then
        # filename, and file exists, post it
        extension=$(echo "${filename##*.}" | tr '[:upper:]' '[:lower:]')
        if [[ $extension == "md" ]] && [[ ! $2 == "markdown" ]]; then
            log "[Warning] Assuming markdown file based on extension"
            format="md"
        elif [[ ! $extension == "md" ]] && [[ $2 == "markdown" ]]; then
            exit "[Error] $filename is not markdown" "$filename isn't markdown. If it is, change the extension."
        elif [[ $extension == "md" ]]; then format="md";
        elif [[ $extension == "html" ]]; then format="html";
        else
            log "[Warning] Unknown extension. Assuming file is html"
            format="html"
        fi
        backup
        log "[Info] Going to post $filename"
        post $format $filename
    elif [[ ! -f "$filename" ]]; then
        # filename, but file doesn't exist
        exit "[Error] $filename does not exist" "$filename does not exist"
    fi
fi
#############

#
# rebuild option
################
if [[ $1 == "rebuild" ]]; then
    backup
    echo "(1/3) Rebuild index, archive, and feed? This will apply"
    echo -n "any changes to variables. Do this? (y/N) "
    read rebuildResponse; rebuildResponse=$(echo $rebuildResponse | tr '[:upper:]' '[:lower:]')
    [[ "$rebuildResponse" == "y" ]] && buildIndex && buildArchive && buildFeed
    echo "(2/3) Rebuild header and footer? This will undo customizations,"
    echo -n "but apply any changes to variables. Do this? (y/N) "
    read rebuildResponse; rebuildResponse=$(echo $rebuildResponse | tr '[:upper:]' '[:lower:]')
    [[ "$rebuildResponse" == "y" ]] && createHeaderFooter "overwrite"
    echo "(3/3) Rebuild css? This will undo customizations."
    echo -n "Do this? (y/N) "
    read rebuildResponse; rebuildResponse=$(echo $rebuildResponse | tr '[:upper:]' '[:lower:]')
    [[ "$rebuildResponse" == "y" ]] && createCss "overwrite"
    sync
fi
#############

#
# reset option
##############
if [[ $1 == "reset" ]]; then
    echo "This will delete the following."
    echo "$global_htmlDir/ and subdirs (if any)"
    echo "$global_sourceDir/ and subdirs (if any)"
    echo "$global_draftsDir/ and subdirs (if any)"
    echo "$global_headerFile"
    echo "$global_footerFile"
    echo "You do have $global_backupFile as a backup, but still be sure you want"
    echo "to perform this action. If you are sure, type \"absolutely\""
    echo -n ">"
    read response; 
    if [[ "$response" == "absolutely" ]]; then
        backup
        log "[Info] Reseting"
        rm -r "$global_htmlDir"
        log "[Info] Removed $global_htmlDir"
        rm -r "$global_sourceDir"
        log "[Info] Removed $global_sourceDir"
        rm -r "$global_draftsDir"
        log "[Info] Removed $global_draftsDir"
        rm "$global_headerFile" "$global_footerFile"
        log "[Info] Removed $global_headerFile and $global_footerFile"
        log "[Info] Reset complete"
        echo "Reset complete"
        sync
    else
        echo "Did not reset"
        log "[Info] Reset canceled"
    fi
fi
##############
exit
