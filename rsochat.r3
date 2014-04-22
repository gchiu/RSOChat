Rebol [
	title: "Rebol Stack Overflow Chat Client"
	author: "Graham Chiu"
	rights: "BSD"
	date: [17-June-2013 19-June-2013 21-June-2013]
	version: 0.0.9
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
            21-June-2013 using a closure for the mini-http function appears to delay the crashes, removed unused code
	22-April-2014 - added a facebook image check - untested
			- checking for posting while not logged in
          }

]

if not value? 'to-text [
	do funct [] [
		either exists? %r3-gui.r3 [
			do %r3-gui.r3
		][
			url: body-of :load-gui
			either parse url [thru 'try set url block! to end][
				parse url [word! set url url!]
				write %r3-gui.r3 read url
				do %r3-gui.r3
			][
				load-gui
			]
		]
	]
]

if not value? 'load-json [
	if not exists? %altjson.r3 [
		write %altjson.r3 read https://raw.github.com/gchiu/RSOChat/master/altjson.r3
	]
	do %altjson.r3
]

if not value? 'decode-xml [
	if not exists? %altxml.r3 [
		write %altxml.r3 read https://raw.github.com/gchiu/RSOChat/master/altxml.r3
	]
	do %altxml.r3
]

no-of-messages: 20
lastmessage-no: 14874139 ; 10025800
wait-period: 5.0 ; seconds
tid-1: tid-2: none

bot-cookie: fkey: none

all-messages: []
last-message: make string! 100
lastmessage-no: 0

storage-dir: %messages/
if not exists? storage-dir [
	make-dir storage-dir
]

static-room-id: room-id: 291 room-descriptor: "rebol-and-red"

id-rule: charset [#"0" - #"9"]

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
								set 'bot-cookie get-face cookie-area
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
						; halt
					]
				]
			]
		]
	]
]


unix-to-utc: func [unix [string! integer!]
	/local days d
][
	if string? unix [unix: to integer! unix]
	days: unix / 24 / 60 / 60
	d: 1-Jan-1970 + days
	d/zone: 0:00
	d/second: 0
	d
]

utc-to-local: func [d [date!]][
	d: d + now/zone
	d/zone: now/zone
	d
]

from-now: func [d [date!]][
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

; holds the images and references to them 
; user-id [ image! name ]

image-cache: make block! 20

; how can we run this ??
update-icons: func [url
	/local icon-bar name image-url image link is-image? page gravatar-rule user-id index
] [
	digit: charset [#"0" - #"9"]
	digits: [some digit]
	icon-bar: copy []
	gravatar-rule: union charset [#"0" - #"9"] charset [#"a" - #"z"]
	page: to string! read url
	parse page [thru "update_user"
		some [
			thru "id:" some space copy user-id digits
			thru "name:" thru {("} copy name to {")} thru "email_hash:" thru {"} copy image-url to {"}
			(
				either not index: find image-cache user-id [
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
						append image-cache user-id
						repend/only image-cache [image name]
						repend icon-bar [image name]
						repend/only icon-bar ['set-face 'chat-area rejoin ["@" replace/all name " " "" " "] 'focus 'chat-area]
					]
				] [
					; user is in cache - we're not going to bother updating a user's image for the moment
					; index now points to the image-cache
					repend icon-bar select index user-id
					repend/only icon-bar ['set-face 'chat-area rejoin ["@" replace/all name " " "" " "] 'focus 'chat-area]
				]
			)
		]
	]
	icon-bar
]

grab-icons: func [url
	/local icon-bar name image-url image link is-image? page gravatar-rule user-id
] [
	digit: charset [#"0" - #"9"]
	digits: [some digit]

	icon-bar: copy []
	gravatar-rule: union charset [#"0" - #"9"] charset [#"a" - #"z"]
	;  {!http://graph.facebook.com/100000296050736/picture?type=large}

	page: to string! read url
	parse page [thru "update_user"
		some [
			thru "id:" some space copy user-id digits
			thru "name:" thru {("} copy name to {")} thru "email_hash:" thru {"} copy image-url to {"}
			(
				is-image?: false
				case [
					all [#"!" = first image-url parse image-url [thru "graph.facebook.com/" copy image-url thru "?type=" to end]][
						image-url: rejoin [http://graph.facebook.com/ image-url "small"]
					]
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
					append image-cache user-id
					repend/only image-cache [image name]
					repend icon-bar [image name]
					repend/only icon-bar ['set-face 'chat-area rejoin ["@" replace/all name " " "" " "] 'focus 'chat-area]
				]
			)
		]
	]
	icon-bar
]
http-header: [
	User-Agent: "Mozilla/5.0 (Windows NT 6.1; rv:22.0) Gecko/20100101 Firefox/22.0"
	Accept: "application/json, text/javascript, */*; q=0.01"
	Accept-Language: "en-US,en;q=0.5"
	Accept-Encoding: "gzip, deflate"
	Content-Type: "application/x-www-form-urlencoded; charset=UTF-8"
	X-Requested-With: "XMLHttpRequest"
	Referer: (referrer)
	Cookie: (cookie)
]

fetch-messages: funct [url [url!] header [block!] from [integer!] no-of-messages [integer!] fkey [string!]][
	payload: ajoin ["since=" from "&mode=Messages&msgCount=" no-of-messages "&fkey=" fkey]
	result: write url compose [
		POST
		header
		(payload)
	]

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
					len: length? system/contexts/user/all-messages
					foreach msg messages [
						content: none
						user-name: none
						message-id: 0
						either parse msg [some message-rule] [
							content: trim decode-xml content
							?? message-id
							if all [
								integer? message-id
								not exists? join storage-dir message-id
							] [
								write join storage-dir message-id mold msg
							]
							if message-id > lastmessage-no [
								set 'lastmessage-no message-id
								repend/only system/contexts/user/all-messages [person-id message-id user-name content timestamp]
							]
						] [print ["failed parse" msg]]
					]
				]

				true
			]
		] [true]
	]
	port/awake: func [event /local result messages content message-no message-id data json user-name message-rule parent-id person-id timestamp] f-body
	open port
]
raw-read: func [message-id target [url!]
	/local result err
][
	if error? set/any 'err try [
		either result: mini-http target 'GET "" 60 [
			?? result
			reply message-id result
		][
			reply message-id "HTTP timeout"
		]
	][
		reply message-id mold err
	]
]
extract-http-response: func [http-text [string!]
	/local result code bodytext server-code
][
	digit: charset [#"0" - #"9"]
	either parse http-text [thru "HTTP/1." ["0" | "1"] some space copy code 3 digit some space copy server-code to newline
		thru "^/^/" copy bodytext to end][
		trim/head/tail bodytext
	][
		make object! compose [error: (server-code) code: (code)]
	]
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
speak: func [message /local err result][
	if message = last-message [exit]
	if error? err: try [
		result: to string! write chat-target-url compose/deep compose/deep copy/deep [
			POST
			[(header)]
			(rejoin ["text=" url-encode message "&fkey=" fkey])
		]
	][
		if find err/arg1 "Server error: HTTP/1.1 404 Not Found" [
			alert "You don't seem to be logged in .. check your credentials again"
		]
	]
]

read-messages: func [cnt][
	to string! write read-target-url compose/deep copy/deep [
		POST
		[(header)]
		(rejoin ["since=0&mode=Messages&msgCount=" cnt "&fkey=" fkey])
	]
]
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

update-messages: func [] [
	attempt [
		result: load-json/flat read-messages no-of-messages
		?? result
		messages: result/2
		; now skip thru each message and see if any unread
		foreach msg messages [
			content: user-name: none message-no: 0
			either parse msg [some message-rule] [
				?? msg
				?? message-id
				if all [
					integer? message-id
					not exists? join storage-dir message-no
				][
					write join storage-dir message-no msg
				]
				content: trim decode-xml content
				if message-id > lastmessage-no [
					lastmessage-no: message-id
					repend/only system/contexts/user/all-messages [person-id message-id user-name content timestamp]
				]
			] [print "failed"]
		]
	]
]

tool-bar-inf: now

either exists? %toolbar.r3 [
	print "loading images off disk"
	tool-bar-data: load %toolbar.r3
	tool-bar-inf: info? %toolbar.r3
	tool-bar-inf: tool-bar-inf/date
	?? tool-bar-inf
][
	print "loading images off web"
	tool-bar-data: grab-icons referrer-url
]

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
						update-fld: field ""
					]
					box white
				]
				chat-area: area "" 300x30 options [min-hint: 500x30 detab: true]
				on-key [
					do-actor/style face 'on-key arg 'area
					if all [
						arg/key = #"^/"
						find arg/flags 'control
					][
						do-face sendbtn
					]


				]
				htight 2 [
					sendbtn: button "send" on-action [
						use [txt] [
							txt: get-face chat-area
							if all [
								found? txt
								not empty? txt
							] [
								if txt <> last-message [
									speak txt

									set-face chat-area copy ""
									set 'last-message txt
								]
							]
						]
						;= update toolbar


						if exists? %toolbar.r3 [
							inf: info? %toolbar.r3
							?? tool-bar-inf
							?? inf

							if inf/date > tool-bar-inf [
								print "Updating images"
								append clear head tool-bar-data load %toolbar.r3
								set 'tool-bar-inf inf/date
								?? tool-bar-inf
								show-now tb
							]
						]

						len: length? system/contexts/user/all-messages
						; clear system/contexts/user/all-messages
						print ["loading messages at " now]
						foreach msg read storage-dir [

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

							if not dir? msg [
								msg: load join storage-dir msg
								content: none
								user-name: none
								message-id: 0
								either parse msg [some message-rule] [
									content: trim decode-xml content
									; ?? message-id
									if message-id > lastmessage-no [
										set 'lastmessage-no message-id
										repend/only system/contexts/user/all-messages [person-id message-id user-name content timestamp]
									]
								] [print ["failed parse" msg]]
							]
						]

						data: copy/deep system/contexts/user/all-messages
						foreach msg data [
							msg/5: from-now utc-to-local unix-to-utc msg/5
						]
						; probe data

						SET-FACE/FIELD window-message-table data 'data
						set-face window-update-fld form now/time

						?? len
						probe length? system/contexts/user/all-messages

						if all [
							value? 'len
							integer? len
							len <> length? system/contexts/user/all-messages
						] [
							set-face message-table/names/scr 100%
							do-face message-table/names/scr
						]
						show-now [window-message-table window-update-fld]

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
						forever [
							update-messages
							; update-icons referrer-url
							data: copy/deep system/contexts/user/all-messages
							foreach msg data [
								msg/5: from-now utc-to-local unix-to-utc msg/5
							]

							set-face update-fld form now
							SET-FACE/FIELD message-table data 'data
							set-face message-table/names/scr 100%
							print now
							wait wait-period
						]

					]
					button "Code" yello on-action [
						use [txt][
							if not empty? txt: get-face chat-area [
								; insert 4 spaces infront of each line
								trim/head/tail txt
								replace/all txt "^/" "^/    "
								insert head txt "    "
								set-face chat-area txt
							]
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
									label "Fetch message no: " nom-fld: field "" 50 on-action [
										attempt [
											set 'no-of-messages to integer! arg
											close-window face
										]
									]
									pad
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
		when [enter] on-action [
			set 'window-update-fld update-fld
			set 'window-message-table message-table
			set 'mychat-area chat-area
			; set-face tb tool-bar-data
			set-face time-fld now/time

			set-face time-fld now/time
			show-now time-fld
		]
	]

	;]
	;]
]


