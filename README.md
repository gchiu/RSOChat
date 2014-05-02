RSOChat
=======

Rebol 3 based simple Stack Overflow chat client

## Instructions ##

Download the windows client [r3-view.exe](http://development.saphirion.com/resources/r3-view.exe) from Saphirion's website

And then just run the rsochat.r3 ( or rsochat.reb ) script. It will grab all other files needed.

## Requirements ##

Windows (32 or 64) currently and Wine on Linux.

Rebol3 on linux and presumably Android has issues ( segmentation fault ) on reading some https pages, and https is needed to fetch some images and to grab the cookies.

your StackExchange userid and password

If you use another way of logging on other than StackExchange credentials you'll need the 

fkey
and USR cookie settings from SO chat.

You can pick them up using a header snooping utility in your browser, or use fiddler.

## Use ##

do %rsochat.r3

## Functionality ##

Grab user icons ( once only - no updating )
Send messages
Reply to messages
Edit and delete messages
Send bot commands

## Limitations ##

Too many to list .. it will read the chat ( to a point - since there is no line wrapping in the list ), and you can post.

