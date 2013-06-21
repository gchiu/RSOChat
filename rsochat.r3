Rebol [
	title: "Rebol Stack Overflow Chat Client"
	author: "Graham Chiu"
	rights: "BSD"
	date: [17-June-2013 19-June-2013]
	version: 0.0.6
	instructions: {
            use the r3-view.exe client from Saphirion for windows currently at http://development.saphirion.com/resources/r3-view.exe
            and then just run this client

            do %rsochat.r3

            and then use the "Start" button to start grabbing messages

            ;This R2 script tickles the gui to grab messages
            ;tickle: does [ p: open/direct/lines tcp://localhost:8000 forever [ insert p "read" pick p 1 wait 0:00:5 ]]

          }
	history: {
            17-June-2013 first attempt at using text-table
            19-June-2013 using a server port to simulate a timer .. and gets a MS Visual C++ runtime error :(  So, back to using a forever loop with a wait
            21-June-2013 using a closure for the mini-http function appears to delay the crashes
          }

]

load-gui

if not value? 'load-json [
	if not exists? %altjson.r3 [
		write %altjson.r3 read http://reb4.me/r3/altjson
	]
	do %altjson.r3
]

if not value? 'decode-xml [
	if not exists? %altxml.r3 [
		write %altxml.r3 read http://reb4.me/r3/altxml
	]
	do %altxml.r3
]

no-of-messages: 5
lastmessage-no: 10025800
wait-period: 0:0:5
tid-1: tid-2: none

bot-cookie: fkey: none

all-messages: []
last-message: make string! 100
lastmessage-no: 0

static-room-id: room-id: 291 room-descriptor: "rebol-and-red"

id-rule: charset [#"0" - #"9"]

cnt: 0
increment-cnt: does [
	system/contexts/user/cnt: system/contexts/user/cnt + 1
]

so-chat-url: http://chat.stackoverflow.com/
profile-url: http://stackoverflow.com/users/
chat-target-url: rejoin write-chat-block: [so-chat-url 'chats "/" room-id "/" 'messages/new]
referrer-url: rejoin [so-chat-url 'rooms "/" room-id "/" room-descriptor]
html-url: rejoin [referrer-url "?highlights=false"]
read-target-url: rejoin [so-chat-url 'chats "/" room-id "/" 'events]
delete-url: [so-chat-url 'messages "/" (parent-id) "/" 'delete]

; perhaps not all of this header is required
header: [
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

do load-config: func [] [
	either exists? %rsoconfig.r3 [
		rsoconfig: do load %rsoconfig.r3
		set 'fkey rsoconfig/fkey
		set 'bot-cookie rsoconfig/bot-cookie
	] [
		view [
			title "Enter the StackOverflow Chat Parameters"
			hpanel 2 [
				label "Fkey: " fkey-fld: field 120 ""
				label "Cookie: " cookie-area: area 400x80 "" options [min-hint: 400x80]
				pad 50x10
				hpanel [
					button "OK" on-action [
						either any [
							empty? fkey: get-face fkey-fld
							empty? cookie: get-face cookie-area
						]
						[alert "Both fields required!"]
						[
							either parse get-face cookie-area [to "usr=" copy cookie to "&" to end] [
								set 'bot-cookie cookie ; get-face cookie-area
								set 'fkey get-face fkey-fld
								save %rsoconfig.r3 make object! compose [
									fkey: (fkey) bot-cookie: (bot-cookie)
								]
								close-window face
							] [
								alert "usr cookie not present"
							]
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
]

timestamp:
person-id:
message-id:
parent-id: 0
user-name: make string! 20

message-rule: [
	<event_type> quote 1 |
	<time_stamp> set timestamp integer! |
	<content> set content string! |
	<id> integer! |
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


unix-to-utc: func [unix [string! integer!]
	/local days d
] [
	if string? unix [unix: to integer! unix]
	days: unix / 24 / 60 / 60
	d: 1-Jan-1970 + days
	d/zone: 0:00
	d/second: 0
	d
]

utc-to-local: func [d [date!]] [
	d: d + now/zone
	d/zone: now/zone
	d
]

from-now: func [d [date!]] [
	case [
		d + 7 < now [d]
		d + 1 < now [join now - d " days"]
		d + 1:00 < now [d/time]
		d + 0:1:00 < now [join to integer! divide difference now d 0:1:00 " mins"]
		true [join to integer! divide now/time - d/time 0:0:1 " secs"]
	]
]

unix-now: does [
	60 * 60 * divide difference now/utc 1-Jan-1970 1:00
]

two-minutes-ago: does [
	subtract unix-now 60 * 2
]

grab-icons: func [url
	/local icon-bar name image-url image link is-image?
] [
	icon-bar: copy []
	gravatar-rule: union charset [#"0" - #"9"] charset [#"a" - #"z"]
	page: to string! read url
	parse page [thru "update_user"
		some [
			thru "name:" thru {("} copy name to {")} thru "email_hash:" thru {"} copy image-url to {"}
			(
				is-image?: false
				case [
					#"!" = first image-url [
						is-image?: true
						remove image-url
						append image-url "?g&s=32"
					]
					parse image-url [some gravatar-rule] [
						is-image?: true
						image-url: ajoin [http://www.gravatar.com/avatar/ image-url "?s=32&d=identicon&r=PG"]
					]
				]
				if is-image? [
					link: read to-url image-url
					either find to string! copy/part link 4 "PNG" [
						image: decode 'PNG link
					] [
						image: decode 'JPEG link
					]
					repend icon-bar [image name]
					repend/only icon-bar ['set-face 'chat-area rejoin ["@" replace/all name " " "" " "] 'focus 'chat-area]
				]
			)
		]
	]
	icon-bar
]
awake-client: func [event /local port] [
	port: event/port
	print ["received event of " event/type]
	switch/default event/type [
		read [
			probe to string! port/data
			write port to binary! "ACK^/"
			mini-http/cookies read-target-url 'POST rejoin ["since=0&mode=Messages&msgCount=10&fkey=" fkey] 60
			bot-cookie
			false
		]
		close [close port true]
		error [close port true]
		wrote [read port false]
	] [false]
]

awake-server: func [event /local client] [

	probe event/type

	if event/type = 'accept [
		print "client connection received .."
		client: first event/port
		client/awake: :awake-client
		read client
	]
]

serve: func [web-port /local listen-port] [
	listen-port: open join tcp://: web-port
	listen-port/awake: :awake-server
	print ["listening on port .. " web-port " and r3gui window"]
	wait listen-port
]
do-download: closure [url [url!] content-area [object!] /local port prg progress-bar] [
	prg: 0
	; url: to-url get-face url-field
	port: make port! url
	port/awake: funct [event] [
		switch event/type [
			connect [
				;; Use HTTP's READ actor to send the HTTP request once we are
				;; connected.
				;		append-content progress-panel [progress 1x1]
				;		set 'progress-bar last faces? progress-panel
				;		append log rejoin [now/precise/time " Started download of: " url newline]
				;		set-face content-area log
				read event/port
			]
			read [
				;; Schedule the low-level TCP port for further reading.
				;; (@@ Smells! Should be taken care of by the HTTP scheme.)
				;sice we don't know the total data size we are cheating a bit here ;)
				;		set-face progress-bar set 'prg prg + (1 - prg / 50)
				if event/port/data [
					probe to string! event/port/data
					;show-face content-area to string! event/port/data
					;show-now content-area
				]
				read event/port/state/connection
			]

			done [
				;		remove-content/pos progress-panel progress-bar
				;		show-now progress-panel
				;; Use HTTP's COPY actor to read the full website content once
				;; reading is finished.
				;		append log rejoin [now/precise/time " Finished download of: " url newline]
				;set-face content-area log
				close event/port
				return true
			]
		]
		false
	]
	open port
	;	wait port
]

; mini-http is a minimalistic http implementation


mini-http: closure [url [url!] method [word! string!] code [string!] timeout [integer!]
	/callback cb
	/cookies cookie [string!]
	/local ; result url-obj payload port f-body
] [
	url-obj: http-request: payload: port: none
	unless cookies [cookie: copy ""]

	http-request: {$method $path HTTP/1.0
Host: $host
User-Agent: Mozilla/5.0
Accept: */*
Accept-Language: en-US,en;q=0.5
Accept-Encoding: gzip, deflate
DNT: 1
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
X-Requested-With: XMLHttpRequest
Referer: http://$host
Content-Length: $len
Cookie: $cookie

$code}

	; Content-Type: text/plain; charset=UTF-8

	url-obj: construct/with sys/decode-url url make object! copy [port-id: 80 path: ""]
	if empty? url-obj/path [url-obj/path: copy "/"]
	payload: reword http-request reduce [
		'method method
		'path url-obj/path
		'host url-obj/host
		'len length? code
		'cookie cookie
		'code code
	]
	port: make port! rejoin [
		tcp:// url-obj/host ":" url-obj/port-id
	]

	f-body: compose/deep copy/deep [

		timestamp:
		person-id:
		message-id:
		parent-id: 0
		user-name: make string! 20

		message-rule: [
			<event_type> quote 1 |
			<time_stamp> set timestamp integer! |
			<content> set content string! |
			<id> integer! |
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

		switch/default event/type [
			lookup [open event/port false]
			connect [
				write event/port (to binary! payload)
				event/port/locals: copy #{}
				false
			]
			wrote [read event/port false]
			read [
				append event/port/locals event/port/data
				clear event/port/data
				read event/port
				false
			]
			close done [
				if event/port/data [
					append event/port/locals event/port/data
				]
				result: to string! event/port/locals
				;attempt [
				if parse result [thru "^/^/" copy result to end] [
					json: load-json/flat result
					messages: json/2
					; now skip thru each message and see if any unread
					foreach msg messages [
						content: none
						user-name: none
						message-no: 0

						either parse msg [some message-rule] [
							content: trim decode-xml content
							if message-id > lastmessage-no [
								set 'lastmessage-no message-id
								repend/only system/contexts/user/all-messages [person-id message-id user-name content timestamp]
							]
						] [print ["failed parse" msg]]
					]
					data: copy/deep system/contexts/user/all-messages
					foreach msg data [
						msg/5: from-now utc-to-local unix-to-utc msg/5
					]
					SET-FACE/FIELD window-message-table data 'data
					set-face window-update-fld form now/time
					show-now [window-message-table window-update-fld]
				]

				;]
				true
			]
		] [true]
	]
	port/awake: func [event /local result messages content message-no message-id data json user-name message-rule parent-id person-id timestamp] f-body
	open port
]
raw-read: func [message-id target [url!]
	/local result err
] [
	if error? set/any 'err try [
		either result: mini-http target 'GET "" 60 [
			?? result
			reply message-id result
		] [
			reply message-id "HTTP timeout"
		]
	] [
		reply message-id mold err
	]
]
extract-http-response: func [http-text [string!]
	/local result code bodytext server-code
] [
	digit: charset [#"0" - #"9"]
	either parse http-text [thru "HTTP/1." ["0" | "1"] some space copy code 3 digit some space copy server-code to newline
		thru "^/^/" copy bodytext to end] [
		trim/head/tail bodytext
	] [
		make object! compose [error: (server-code) code: (code)]
	]
]



percent-encode: func [char [char!]] [
	char: enbase/base to-binary char 16
	parse char [
		copy char some [char: 2 skip (insert char "%") skip]
	]
	char
]

url-encode: use [ch mk] [
	ch: charset ["-." #"0" - #"9" #"A" - #"Z" #"-" #"a" - #"z" #"~"]
	func [text [any-string!]] [
		either parse/all text: form text [
			any [
				some ch | end | change " " "+" |
				mk: (mk: percent-encode mk/1)
				change skip mk
			]
		] [to-string text] [""]
	]
]
speak: func [message /local err] [
	if error? set/any 'err try [
		to string! write chat-target-url compose/deep copy/deep [
			POST
			[(header)]
			(rejoin ["text=" url-encode message "&fkey=" fkey])
		]
	] [
		mold err
	]
]

read-messages: func [cnt] [
	to string! write read-target-url compose/deep copy/deep [
		POST
		[(header)]
		(rejoin ["since=0&mode=Messages&msgCount=" cnt "&fkey=" fkey])
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

print "loading images"

tool-bar-data: grab-icons referrer-url

view compose/deep [
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
			tb: tool-bar [(tool-bar-data)] on-action [print arg]
			hpanel [
				vpanel [
					hpanel [
						time-fld: field ""
						update-fld: field "" ; options [ max-hint: 40x5 ] 
					]
					box 30x30
				]
				chat-area: area "" 300x30 options [min-hint: 500x30]
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
						mini-http/cookies read-target-url 'POST rejoin ["since=0&mode=Messages&msgCount=10&fkey=" fkey] 60 bot-cookie

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
					button "Fetch Msgs" green on-action [
						if none? bot-cookie [
							alert "bot cookie not set .. try restarting"
							exit
						]

						mini-http/cookies read-target-url 'POST rejoin ["since=0&mode=Messages&msgCount=10&fkey=" fkey] 60 bot-cookie


						set 'tid-1 set-timer/repeat [
							mini-http/cookies read-target-url 'POST rejoin ["since=0&mode=Messages&msgCount=10&fkey=" fkey] 60 bot-cookie

						] 5.0


					]
					button "Pause Messages" yello on-action [
						clear-timer tid-1
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
						]
					]
				] options [max-hint: 200x100]

				box 60x30
			] options [min-hint: 300x80 max-hint: 1200x110]
		]
		scroll-panell [
			; holds icons and tagged messages

		]
		when [enter] on-action [
			set 'window-update-fld update-fld
			set 'window-message-table message-table
			set 'mychat-area chat-area
			; set-face tb tool-bar-data
			; serve 8000
			set-face time-fld now/time

			set 'tid-2 set-timer/repeat [
				set-face time-fld now/time
				show-now time-fld
			] 1.0
		]
	]

	;]
	;]
]


