#!/bin/bash
########################################################################
#
# README
#
# This is a basic blog generator
# 
########################################################################

# location of config/log files
# values found in here overload defaults in this script
# expected format:
# key="value"
global_config="bashblog2.conf"
global_logFile="bashblog2.log"

# run at beginning of script to generate globals
#
# takes no args
initializeGlobalVariables() {
    global_softwareName="BashBlog2"
    global_softwareVersion="0.1.2a"
    
    global_title="My blog" # blog title
    global_description="Blogger blogging on my blog" # blog subtitle
    global_url="http://example.com/blog" # top-level URL for accessing blog
    global_author="John Doe" # your name
    global_authorUrl="$global_url" # optional link to a a facebook profile, etc.
    global_email="johndoe@example.com" # your email
    global_license="CC by-nc-nd" # "&copy;" for copyright, for example
   
    global_indexFile="index.html" # index page, best to leave alone
    global_archiveFile="archive.html" # page to list all posts
    global_headerFile="header.html" # header file  # change to use something
    global_footerFile="footer.html" # footer file  # other than default
    
    global_sourceDir="source" # dir for easy-to-edit source             # best  
    global_draftsDir="drafts" # dir for drafts                          # to
    global_htmlDir="html" # dir for final html files                    # leave
    global_previewDir="$global_htmlDir/preview" # dir for previews      # these
    global_tempDir="/tmp/$global_softwareName" # dir for pending files  # alone
    
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
    echo "Usage: $0 command [filename]"
    echo ""
    echo "Commands:"
    echo "    edit [filename] .............. edit a file and republish if necessary"
    echo "    post [markdown] [filename] ... publish a blog entry"
    echo "                                   if markdown not specified, then assume html"
    echo "                                   if no filename, start from scratch"
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
    local datetime=$(date +'%Y%m%d%H%M%S')
    if [[ $1 == "md" ]]; then local content="This is the body of your post. You may format with **markdown**.\n\nUse as many lines as you wish.";
    else local content="<p>This is the body of your post. You may format with <b>html</b></p>\n\n<p>Use as many lines as you wish.</p>"; fi
    echo "---------DO-NOT-EDIT-THIS-SECTION----------"  > $2
    echo $1                                            >> $2 # format 
    echo $datetime                                     >> $2 # original datetime
    echo $datetime                                     >> $2 # edit datetime
    echo "----------------POST-CONTENT---------------" >> $2
    echo "Title goes on this line"                     >> $2
    echo "----"                                        >> $2
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
        log "[Info] Starting sync"
        $global_syncFunction
        log "[Info] End of sync"
    else
        log "[Info] No sync function"
    fi
    
}

# edit a file and start the process of republishing if needed
# got here with "./bashblog2.sh edit filename"
#
# $1    filename to edit
edit() {
    $EDITOR "$1"
}

# parse the given file into html
# and put it all into the given filename
#
# $1    file to parse
# $2    dir to put parsed .html file into
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
    local line
    while read line; do
        if [[ "$line" == "---------DO-NOT-EDIT-THIS-SECTION----------" ]]; then
            read line # format content is in, "md" or "html"
            if [[ -z "$format" ]]; then
                format="$line"
                if [[ $format != "md" ]] && [[ $format != "html" ]]; then
                    echo "Couldn't parse file: invalid format"
                    exit "[Error] Couldn't parse file: invalid format"
                fi
            fi
            read line # posting date, should never change
            if [[ -z "$postDate" ]]; then
                postDate="$line"
                if [[ ! $postDate =~ ^[0-9]+$ ]]; then
                    echo "Couldn't parse file: invalid date"
                    exit "[Error] Couldn't parse file: invalid date"
                fi
            fi
            read line # edit date, changes when editing after publication
            if [[ -z "$editDate" ]]; then
                editDate="$line"
                if [[ ! $editDate =~ ^[0-9]+$ ]]; then
                    echo "Couldn't parse file: invalid date"
                    exit "[Error] Couldn't parse file: invalid date"
                fi
            fi
        elif [[ "$line" == "----------------POST-CONTENT---------------" ]]; then
            read line # title, then also convert into filename
            title="$line" 
            # get filename based on title: all lower case, spaces to dashes, all alphanumeric
            filename="$2/$(echo $title | tr [:upper:] [:lower:] | sed 's/\ /-/g' | tr -dc '[:alnum:]-').html"
            read line # spacer between title and content
        elif [[ "$line" != "---------POST-TAGS---ONE-PER-LINE----------" ]] && [[ $onTags == "false" ]]; then
            # get everything before tag divider into the content variable
            [[ ! -z "$content" ]] && content="$content\n$line" || content="$line"
        else
            onTags="true"
            # get tags, except first thing will be the divider so continue first
            [[ "$line" == "---------POST-TAGS---ONE-PER-LINE----------" ]] && continue
            if [[ $line =~ ^.*\;.*$ ]]; then
                echo "Coudln't parse file: tags can't have \";\" in them"
                exit "[Error] Couldn't parse file: bad tags"
            else
                # append latest tag to list, dividing each with ";"
                [[ ! -z "$tags" ]] && tags="$tags;$line" || tags="$line"
            fi
        fi
    done < "$1"
    
    createHtmlPage $format $postDate $editDate "$title" "$content" "$tags" "$filename"
}

# takes parsed information 
# and turns into an html file 
# ready for publishing (or previewing)
#
# $1    format, "md" or "html"
# $2    date & time of original posting
# $3    date & time of latest edit
# $4    title of post
# $5    content of post
# $6    tags of post, if any
# $7    filename where everything goes
# returns $7
createHtmlPage() {
    echo $7
}

# publish a file
# got here with "./bashblog2.sh post [filename]"
#
# $1    format, "md" or "html"
# $2    filename, optional
post() {
    local format=$1
    local filename="$filename"
    # if no filename passed, posting a new file. Make a temp file
    if [[ -z "$filename" ]]; then
        filename="$global_tempDir/$RANDOM$RANDOM$RANDOM"
        fillPostTemplate $format $filename
    fi
    # do any editing if the blogger wants to
    local postResponse="e"
    while [[ $postResponse != "p" ]] && [[ $postResponse != "s" ]] && [[ $postResponse != "d" ]]
    do
        $EDITOR "$filename"
        # see if blogger wants to preview post
        local previewResponse="y"
        echo -n "Preview post? (y/N) "
        read previewResponse && echo
        previewResponse=$(echo $previewResponse | tr '[:upper:]' '[:lower:]')
        if [[ $previewResponse == "y" ]]; then
            # yes he does
            log "[Info] Generating preview"
            local parsedPreview=$(parse "$filename" "$global_previewDir") # filename of where preview is on disk
            # possible bug: it is not safe to assume that we can remove $global_htmlDir because $global_previewDir is a sub dir of it
            # it may not be a subdir of $global_htmlDir. This is why it those settings are best left alone!
            local url=$global_url"$(echo $parsedPreview | sed "s/$global_htmlDir//")" # url of preview, assuming sync is set up
            sync
            echo "See $parsedPreview"
            echo "or $url"
            echo "depending on your configuration"
        else
            # do nothing
            echo "" &> /dev/null
        fi
        
        echo -n "(p)ublish, (E)dit, (s)ave draft, (d)iscard: "
        read postResponse && echo
        postResponse=$(echo $postResponse | tr '[:upper:]' '[:lower:]')
    done
    if [[ $postResponse == "p" ]]; then
        # todo
        log "[Info] publishing"
    elif [[ $postResponse == "s" ]]; then
        # todo
        log "[Info] saving"
    elif [[ $postResponse == "d" ]]; then
        # todo
        log "[Info] moving to drafts"
    fi
    
}

# backup desired files to compressed tarball
# best to leave $global_backupList alone
#
# takes no args
backup() {
    local backupList="$global_sourceDir $global_draftsDir $global_htmlDir $global_tempDir"
    tar cfz $global_backupFile $backupList &> /dev/null
    [[ $? -ne 0 ]] && log "[Warning] Backup error"
    chmod 600 $global_backupFile
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
# $1 optional message to log
exit() {
    [[ ! -z "$1" ]] && log "$1"
    log "[Info] Ending run"
    builtin exit # exit program
}

########################################################################
# main
########################################################################
log "[Info] Starting run"
detectDateVersion
initializeGlobalVariables # initalize and load global variables from config
mkdir -p "$global_sourceDir" "$global_draftsDir" "$global_htmlDir" "$global_previewDir" "$global_tempDir"
[[ -f "$global_config" ]] && source "$global_config" &> /dev/null
# make sure $EDITOR is set
[[ -z $EDITOR ]] && echo "Set \$EDITOR enviroment variable" && exit "[Error] \$EDITOR not exported"

# check for valid arguments
# chain them together like [[  ]] && [[  ]] && ... && usage && exit
[[ $1 != "edit" ]] && [[ $1 != "post" ]] && usage && exit

#
# edit option
#############
# $1    "edit"
# $2    filename
if [[ $1 == "edit" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "Enter a valid file to edit"
        exit "[Error] No file passed"
    elif [[ ! -f "$2" ]]; then
        echo "$2 does not exist"
        exit "[Error] File does not exist"
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
    
    if [[ -z "$filename" ]]; then
        # no filename, generate new file
        if [[ $2 == "markdown" ]]; then format="md";
        else format="html"; fi
        log "[Info] Starting post process on new post"
        post $format
    elif [[ -f "$filename" ]]; then
        # filename, and file exists, post it
        extension=$(echo "${filename##*.}" | tr '[:upper:]' '[:lower:]')
        if [[ $extension == "md" ]] && [[ ! $2 == "markdown" ]]; then
            log "[Warning] Assuming markdown file based on extension"
            format="md"
        elif [[ ! $extension == "md" ]] && [[ $2 == "markdown" ]]; then
            echo "$filename isn't markdown. If it is, change the extension."
            exit "[Error] $filename is not markdown"
        elif [[ $extension == "md" ]]; then format="md";
        elif [[ $extension == "html" ]]; then format="html";
        else
            log "[Warning] Unknown extension. Assuming file is html"
            format="html"
        fi
        log "[Info] Starting post process on $filename"
        post $format $filename
    elif [[ ! -f "$filename" ]]; then
        # filename, but file doesn't exist
        echo "$filename does not exist"
        exit "[Error] File does not exist"
    fi
fi
#############

exit
