Rebol [
    title: "Rebol Stack Overflow Chat Client"
    author: "Graham Chiu"
    rights: "BSD"
    date: 17-June-2013
    version: 0.0.2
          instructions: {
            use the r3-view.exe client from Saphirion for windows currently at http://development.saphirion.com/resources/r3-view.exe
            and then just run this client

            do %rsochat.r3

            and then use the "Start" button to start grabbing messages
          }
          history: {
            17-June-2013 first attempt at using text-table


          }

]

load-gui

if not value? 'load-json [
    do http://reb4.me/r3/altjson
]

if not value? 'decode-xml [
    do http://reb4.me/r3/altxml
]

no-of-messages: 5
lastmessage-no: 10025800
wait-period: 1

bot-cookie: fkey: none

all-messages: [ ]
last-message: make string! 100

static-room-id: room-id: 291 room-descriptor: "rebol-and-red"

id-rule: charset [ #"0" - #"9" ]

so-chat-url: http://chat.stackoverflow.com/ 
profile-url: http://stackoverflow.com/users/
chat-target-url: rejoin write-chat-block: [ so-chat-url 'chats "/" room-id "/" 'messages/new  ]
referrer-url: rejoin [ so-chat-url 'rooms "/" room-id "/" room-descriptor ]
html-url: rejoin [ referrer-url "?highlights=false" ]
read-target-url: rejoin [ so-chat-url 'chats "/" room-id "/" 'events ]
delete-url: [ so-chat-url 'messages "/" (parent-id) "/" 'delete ] 

; perhaps not all of this header is required
header:  [
    Host: "chat.stackoverflow.com"
    Origin: "http://chat.stackoverflow.com"
    Accept: "application/json, text/javascript, */*; q=0.01"
    X-Requested-With: "XMLHttpRequest"
    Referer: (referrer-url)
    Accept-Encoding: "gzip,deflate"
    Accept-Language: "en-US"
    Accept-Charset: "ISO-8859-1,utf-8;q=0.7,*;q=0.3"
    Content-Type: "application/x-www-form-urlencoded"
    cookie: (bot-cookie)
]

either exists? %rsoconfig.r3 [
    rsoconfig: do load %rsoconfig.r3
          fkey: rsoconfig/fkey
          bot-cookie: rsoconfig/bot-cookie
] [
    view [
        title "Enter the StackOverflow Chat Parameters"
        hpanel 2 [
            label "Fkey: " fkey-fld: field 120 ""
            label "Cookie: " cookie-area: area 400x80 "" options [ min-hint: 400x80 ]
            pad 50x10
            hpanel [
                button "OK" on-action [
                                            either any [
                                                empty? fkey: get-face fkey-fld
                                                empty? bot-cookie: get-face cookie-area
                                            ][  alert "Both fields required!" ]
                                            [
                                                save %rsoconfig.r3 make object! compose [ fkey: (fkey) bot-cookie: (bot-cookie) ]
                                                close-window face 
                                            ]
                ]
                button "Cancel" red on-action [
                    close-window face
                    halt
                ]
            ]
        ]
    ]
]

timestamp: 
person-id:
message-id:
parent-id: 0
user-name: make string! 20

message-rule: [ 
    <event_type> quote 1  |
    <time_stamp> set timestamp integer! |
    <content> set content string! |
    <id>  integer! |
    <user_id> set person-id integer! |
    <user_name> set user-name string! |
    <room_id> integer! |
    <room_name> string! |
    <message_id> set message-id integer! |
    <parent_id> set parent-id integer! |
    <show_parent> logic! |
    tag! skip |
    end 
]


unix-to-utc: func [ unix [string! integer!]
    /local days d 
][
    if string? unix [ unix: to integer! unix ]
    days: unix / 24 / 60 / 60
    d: 1-Jan-1970 + days
    d/zone: 0:00
    d/second: 0
    d
]

utc-to-local: func [ d [ date!]][
    d: d + now/zone
    d/zone: now/zone
    d
]

from-now: func [ d [date!]][
    case [
        d + 7 < now [ d ]
        d + 1 < now [ join now - d " days" ]
        d + 1:00 < now [ d/time ]
        d + 0:1:00 < now [ join to integer! divide difference now d 0:1:00 " mins" ]
        true [ join to integer! divide now/time - d/time 0:0:1 " secs" ]	
    ]
]

unix-now: does [
    60 * 60 * divide difference now/utc 1-Jan-1970 1:00
]

two-minutes-ago: does [
    subtract unix-now 60 * 2
]

percent-encode: func [char [char!]][
        char: enbase/base to-binary char 16
        parse char [
            copy char some [char: 2 skip (insert char "%") skip]
        ]
        char
    ]

url-encode: use [ch mk][
    ch: charset ["-." #"0" - #"9" #"A" - #"Z" #"-" #"a" - #"z" #"~"]
     func [text [any-string!]][
        either parse/all text: form text [
            any [
                some ch | end | change " " "+" |
                mk: (mk: percent-encode mk/1)
                change skip mk
            ]
       ][to-string text][""]
    ]
]
speak: func [ message /local err ][
    if error? set/any 'err try [
        to string! write chat-target-url compose/deep  copy/deep [
            POST
            [ 	(header) ]
            (rejoin [ "text=" url-encode message "&fkey=" fkey ])
        ]
    ][
        mold err
    ]
]

read-messages: func [ cnt][
        to string! write read-target-url compose/deep  copy/deep [
            POST
            [ 	(header) ]
            (rejoin [ "since=0&mode=Messages&msgCount=" cnt "&fkey=" fkey ])
        ]
]
update-messages: func [] [
    attempt [
        result: load-json/flat read-messages no-of-messages
        messages: result/2
        ; now skip thru each message and see if any unread
        foreach msg messages [
            content: user-name: none message-no: 0
            either parse msg [some message-rule] [
                content: trim decode-xml content
                if message-id > lastmessage-no [
                    lastmessage-no: message-id
                    repend/only system/contexts/user/all-messages [person-id message-id user-name content timestamp]
                ]
            ] [print "failed"]
        ]
    ]
]

view [
    ;tab-box [
    ;    "Rebol/Red" [
            hpanel [
                vpanel [
                    message-table: text-table 200x400 ["Username" #3 150 "Chat" #4 900 "Time" #5 10]
                    [] on-action [
                        row: get-face face
                        column: to integer! row/x
                        row: to integer! row/y
                        row-data: pick system/contexts/user/all-messages row
                        switch column [
                            3 [
                                set-face chat-area ajoin ["@" row-data/3 " " get-face chat-area]
                                focus chat-area
                            ]
                            4 [
                                set-face chat-area row-data/4
                            ]
                            5 [
                                set-face chat-area ajoin [":" row-data/2 " " get-face chat-area]
                                focus chat-area
                            ]
                        ]
                    ]
                    hpanel [
                        box 30x30 chat-area: area "" 300x30 options [min-hint: 500x30]
                        htight 2 [
                            button "send" on-action [
                                use [txt] [
                                    txt: get-face chat-area
                                    if all [
                                        found? txt
                                        not empty? txt
                                    ] [
                                        speak txt
                                        set-face chat-area copy ""
                                        set 'last-message txt
                                    ]
                                ]
                            ]
                            button "Last Msg" on-action [
                                set-face chat-area last-message
                            ]
                            button "Clear" gold on-action [
                                set-face chat-area ""
                            ]
                            button "RebolBot" on-action [
                                set-face chat-area join "@rebolbot " get-face chat-area
                                focus chat-area
                            ]
                            button "start" green on-action [
                                forever [
                                    update-messages
                                    data: copy/deep system/contexts/user/all-messages
                                    foreach msg data [
                                        msg/5: from-now utc-to-local unix-to-utc msg/5
                                    ]
                                    SET-FACE/FIELD message-table data 'data
                                    wait wait-period
                                ]
                            ]
                            button "Stop" red on-action [
                                close-window face
                                halt
                            ]
                            button "Settings" on-action [
                                view [
                                    vpanel [
                                        title "Settings"
                                        hpanel [
                                            label "Fetch message no: " nom-fld: field "" on-action [
                                                                                                attempt [
                                                                                                    set 'no-of-messages to integer! arg
                                                                                                    set 'lastmessage-no 0
                                                                                                    close-window face
                                                                                                ] 
                                                                                            ]
                                        ]
                                        hpanel [
                                            button "Cancel" red on-action [close-window face]
                                        ]
                                                                                  bar
                                                                                  hpanel 2 [
                                                                                            label "fkey" fk-fld: field
                                                                                            label "cookie" cookie-area: area
                                                                                  ] options [black border-size: [1x1 1x1]]
                                    ]
                                    when [load] on-action [
                                                                                    set-face nom-fld no-of-messages
                                                                                    set-face fk-fld fkey
                                                                                    set-face cookie-area bot-cookie
                                                                        ]
                                ]
                            ]
                        ] options [max-hint: 200x100]

                        box 60x30
                    ] options [min-hint: 300x80 max-hint: 1200x110]
                ]
                scroll-panell [
                    ; holds icons and tagged messages

                ]
            ]

        ;]
    ;]
]

