Rebol [
	title: "Rebol Stack Overflow Chat Client"
	File: %rsochat.r3
	author: "Graham Chiu"
	rights: "BSD"
	date: [17-June-2013 19-June-2013 21-June-2013 4-May-2014]
	version: 0.0.99
	instructions: {
            use the r3-view.exe client from Saphirion for windows currently at http://development.saphirion.com/resources/r3-view.exe
            and then just run this client

            do %rsochat.r3

            and then use the "Fetch Msgs" button to start grabbing messages

          }
	history: {
                17-June-2013 first attempt at using text-table
                19-June-2013 using a server port to simulate a timer .. and gets a MS Visual C++ runtime error :(  So, back to using a forever loop with a wait
                21-June-2013 using a closure for the mini-http function appears to delay the crashes, removed unused code
                22-April-2014 - added a facebook image check - untested
            - checking for posting while not logged in
                27-April-2014 custom prot-http to grab images, and redirects.  Grabs cookies now and fkey
                0.0.92 added most of the bot commands as text-table
                0.0.93 added delete message and edit message functionality
                1-May-2014 added some more error trapping
                2-May-2014 removed 'needs header .. odd errors occur
                3-May-2014 0.0.98 rearranged layout a little, added a toggle to fetch messages.  Icon bar is removed when toggled off but not replaced yet when restarted
                4-May-2014 0.9.99 client can now switch rooms, update icon bars and trap malformed messages ( need to track down how they are being saved )
                6-May-2014 0.1.0 reorganized name space naming so u: system/contexts/user
          }
]

logfile: %events.reb
; if not exists? logfile [write logfile ""]
write logfile ""
debug: true

do rsolog: func [event][
	if debug [
		print ["logging event" event]
		write/append logfile join reform [now/time event] newline
	]
	event
] "starting .. "

foreach [module test][
	%prot-http.r3 idate-to-idate
	%r3-gui.r3 to-text
	%altjson.r3 load-json
	%altxml.r3 load-xml
	%altwebform.r load-webform
][
	unless value? :test [
		unless exists? module [
			rsolog join "fetching " module

			switch/default module [
				%r3-gui.r3 [
					test: body-of :load-gui
					either parse test [thru 'try set test block! to end][
						parse test [word! set test url!]
						write module read test
						do rsolog module
					][
						load-gui
					]
				]
				%altwebform.r [
					write module read join http://reb4.me/r3/ module
				]

				%prot-http.r3 [
					write module read rsolog join https://raw.githubusercontent.com/gchiu/Rebol3/master/protocols/ module
				]
			][
				write module read rsolog join https://raw.githubusercontent.com/gchiu/RSOChat/master/ module
			]
		]

		do rsolog module
	]
]

; create a short to the user global context
u: self

login2so: func [email [email!] password [string!] chat-page [url!]
	/local fkey root loginpage cookiejar result err configobj
][
	configobj: make object! [fkey: copy "" bot-cookie: copy ""]
	fkey: none
	root: https://stackoverflow.com
	; grab the first fkey from the login page
	print "reading login page"
	loginpage: to string! read https://stackoverflow.com/users/login
	print "read ..."
	if parse loginpage [thru "se-login-form" thru {action="} copy action to {"} thru "fkey" thru {value="} copy fkey to {"} thru {"submit-button"} thru {value="} copy login to {"} to end][
		postdata: to-webform reduce ['fkey fkey 'email email 'password password 'submit-button login]
		if error? err: try [
			print "posting"
			result: to-string write join root action postdata
		][
			print "parsing"
			cookiejar: reform err/arg2/headers/set-cookie
			parse cookiejar [to "usr=" copy cookiejar to ";"]
			result: write chat-page compose/deep [GET [cookie: (cookiejar)]]
			result: reverse decode 'markup result
			; now grab the new fkey for the chat pages
			foreach tag result [
				if tag? tag [
					if parse tag [thru "fkey" thru "hidden" thru "value" thru {"} copy fkey to {"} to end][
						fkey: to string! fkey
						break
					]
				]
			]
		]
		configobj/fkey: fkey
		configobj/bot-cookie: cookiejar
	]
	configobj
]


no-of-messages: 20
wait-period: 5.0 ; seconds

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

; chat-target-url: rejoin write-chat-block: [so-chat-url 'chats "/" room-id "/" 'messages/new]
chat-target-url: func [room-id][
	rejoin [so-chat-url 'chats "/" room-id "/" 'messages/new]
]

; referrer-url: rejoin [so-chat-url 'rooms "/" room-id "/" room-descriptor]

referrer-url: func [room-id room-descriptor][
	rejoin [so-chat-url 'rooms "/" room-id "/" room-descriptor]
]

; html-url: rejoin [referrer-url "?highlights=false"]

html-url: func [][
	rejoin [referrer-url room-id room-descriptor "?highlights=false"]
]

; read-target-url: rejoin [so-chat-url 'chats "/" room-id "/" 'events]

read-target-url: func [room-id][
	rejoin [so-chat-url 'chats "/" room-id "/" 'events]
]

delete-url: [so-chat-url 'messages "/" parent-id "/" 'delete]
edit-url: [so-chat-url 'messages "/" parent-id]


; perhaps not all of this header is required
header: [
	Host: "chat.stackoverflow.com"
	Origin: "http://chat.stackoverflow.com"
	Accept: "application/json, text/javascript, */*; q=0.01"
	X-Requested-With: "XMLHttpRequest"
	Referer: (referrer-url room-id room-descriptor)
	Accept-Encoding: "gzip,deflate"
	Accept-Language: "en-US"
	Accept-Charset: "ISO-8859-1,utf-8;q=0.7,*;q=0.3"
	Content-Type: "application/x-www-form-urlencoded"
	cookie: (bot-cookie)
]
if not exists? %rsoconfig.r3 [
	view/modal [
		vgroup [
			label "Enter StackExchange Credentials and Room"
			vgroup [
				hgroup [label "Email: " emailfld: field]
				hgroup [label "Password: " passwordfld: field]
				hgroup [label "Room ID: " roomidfld: field "291"]
				hgroup [label "Room Descriptor: " descriptorfld: field "rebol-and-red"]

			]
			hgroup [
				button "Login" on-action [
					if all [
						not empty? email: get-face emailfld
						not empty? password: get-face passwordfld
						not empty? room-id: get-face roomidfld
						not empty? room-descriptor: get-face descriptorfld
						attempt [integer! = type? room-id: load room-id]
						attempt [email! = type? email: load email]
					][
						; okay, all is well
						close-window face
						result: login2so email password referrer-url room-id room-descriptor
						rsolog mold result
						save %rsoconfig.r3 append result compose [room-id: (room-id) room-descriptor: (room-descriptor)]
					]
				]
				button "Cancel" red on-action [
					close-window face
				]
				when [enter] on-action [focus emailfld]
			]
		]
	]
]

do load-config: func [] [
	either exists? %rsoconfig.r3 [
		if error? err: try [
			rsoconfig: do load %rsoconfig.r3
			set 'fkey rsoconfig/fkey
			set 'bot-cookie trim/tail rsoconfig/bot-cookie
			set 'room-id rsoconfig/room-id
			set 'room-descriptor rsoconfig/room-descriptor
		][
			alert "rsoconfig.r3 is corrupt - use settings to set them again"
		]
	] [
		; only get here if cancelled the above
		view [
			title "Enter the StackOverflow Chat Parameters"
			hpanel 2 [
				label "Fkey: " fkey-fld: field 120 ""
				label "Cookie: " cookie-area: field 120
				label "Chat room-id" room-id-fld: field 20
				label "Room Descriptor" room-descriptor-fld: field 120
				pad 50x10
				hpanel [
					button "OK" on-action [
						either any [
							empty? fkey: get-face fkey-fld
							empty? cookie: get-face cookie-area
							empty? room-id: get-face room-id-fld
							empty? room-descriptor: get-face room-descriptor-fld
						][
							alert "All fields required!"]
						[
							if not parse cookie ["usr=t=" to end][
								alert "usr cookie needed of form: usr=t=xxxxx&s=xxxxx"
								exit
							]
							either attempt [room-id: to integer! room-id][
								set 'bot-cookie cookie
								set 'fkey fkey
								set 'room-descriptor room-descriptor
								set 'room-id room-id
								save %rsoconfig.r3 make object! compose [
									fkey: (fkey) bot-cookie: (bot-cookie)
									room-id: (room-id) room-descriptor: (room-descriptor)
								]
								close-window face
							][
								alert "Room ID needs to be an integer!"
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

update-icons: func [url
	/local icon-bar name image-url image link is-image? page gravatar-rule user-id index err err2
] [
	rsolog url
	digit: charset [#"0" - #"9"]
	digits: [some digit]
	icon-bar: copy []
	gravatar-rule: union charset [#"0" - #"9"] charset [#"a" - #"z"]
	if error? err: try [
		page: to string! read url
	][
		rsolog mold err
		return icon-bar
	]
	if error? err: try [
		parse page [thru "update_user"
			some [
				thru "id:" some space copy user-id digits
				thru "name:" thru {("} copy name to {")} thru "email_hash:" thru {"} copy image-url to {"}
				(
					either not index: find image-cache user-id [
						case [
							all [
								#"!" = first image-url
								parse image-url [thru "graph.facebook.com/" copy image-url thru "?type=" to end]
							][
								image-url: ajoin [http://graph.facebook.com/ image-url "small"]
								is-image?: true
								print 'facebook

							]
							#"!" = first image-url [
								is-image?: true
								remove image-url
								append image-url "?g&s=32"
								print 'stack-imgur
							]
							parse image-url [some gravatar-rule] [
								is-image?: true
								image-url: ajoin [http://www.gravatar.com/avatar/ image-url "?s=32&d=identicon&r=PG"]
								print 'Gravatar
							]
						]
						if is-image? [
							?? image-url
							if error? err2: try [
								link: read to-url image-url
							][
								; check for redirect to other host as used in facebook
								if all [find err2/arg1 "Redirect" url? err2/arg3][
									print "*** error redirect ****"
									link: read err2/arg3
								]
							]
							; examine the binary to see what type of image it is - can't rely on extension
							imagetext: to string! copy/part link 20
							case [
								find/part imagetext "PNG" 4 [
									image: decode 'PNG link
									print 'PNG
								]
								find/part imagetext "JFIF" 10 [
									image: decode 'JPEG link
									print 'JPEG
								]
								find/part imagetext "GIF89" 6 [
									attempt [
										if block? image: load link [image: copy blank-img]
									]
									print 'GIF
								]
								true [
									image: copy blank-img
									print 'Unknown
								]
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
		rsolog "returning new icon bar"
		rsolog length? icon-bar
	][
		; should log a timeout or other error somewhere
		rsolog "failed to get icon bar"
		rsolog mold err
	]
	icon-bar
]


blank-img: make image! 128x128

grab-icons: func [url
	/local icon-bar name image-url image link is-image? page gravatar-rule user-id digit digits
	lastimage err err2
] [
	if error? err: try [
		lastimage: none
		digit: charset [#"0" - #"9"]
		digits: [some digit]

		icon-bar: copy []
		gravatar-rule: union charset [#"0" - #"9"] charset [#"a" - #"z"]
		;  {!http://graph.facebook.com/100000296050736/picture?type=large}
		if error? err2: try [
			page: to string! read url
		][
			rsolog mold err2
			return icon-bar
		]
		parse page: to string! read url [thru "update_user"
			some [
				thru "id:" some space copy user-id digits
				thru "name:" thru {("} copy name to {")} thru "email_hash:" thru {"} copy image-url to {"}
				(
					is-image?: false
					case [
						all [
							#"!" = first image-url
							parse image-url [thru "graph.facebook.com/" copy image-url thru "?type=" to end]
						][
							image-url: ajoin [http://graph.facebook.com/ image-url "small"]
							is-image?: true
							print 'facebook

						]
						#"!" = first image-url [
							is-image?: true
							remove image-url
							append image-url "?g&s=32"
							print 'stack-imgur
						]
						parse image-url [some gravatar-rule] [
							is-image?: true
							image-url: ajoin [http://www.gravatar.com/avatar/ image-url "?s=32&d=identicon&r=PG"]
							print 'Gravatar
						]
					]
					if is-image? [
						rsolog image-url
						if error? err2: try [
							link: read to-url image-url
						][
							; check for redirect to other host as used in facebook
							if all [find err2/arg1 "Redirect" url? err2/arg3][
								print "*** error redirect ****"
								link: read err2/arg3
							]
						]
						; examine the binary to see what type of image it is - can't rely on extension
						imagetext: to string! copy/part link 20
						case [
							find/part imagetext "PNG" 4 [
								image: decode 'PNG link
								print 'PNG
							]
							find/part imagetext "JFIF" 10 [
								image: decode 'JPEG link
								print 'JPEG
							]
							find/part imagetext "GIF89" 6 [
								attempt [
									if block? image: load link [image: copy blank-img]
								]
								print 'GIF
							]
							true [
								image: copy blank-img
								print 'Unknown
							]
						]

						append image-cache user-id
						repend/only image-cache [image name]

						repend icon-bar [image name]
						repend/only icon-bar ['set-face 'chat-area rejoin ["@" replace/all name " " "" " "] 'focus 'chat-area]
					]
				)
			]
		]
		rsolog "exiting grab-icons function"
	][
		if equal? err/id 'not-connected [alert "Room-Descriptor may be wrong!"]
		rsolog mold err
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
delete-message: func [parent-id [integer!]
	/local err result
][
	bind delete-url 'parent-id
	if error? err: try [
		result: to string! write rejoin delete-url compose/deep compose/deep copy/deep [
			POST
			[(header)]
			(rejoin ["fkey=" fkey])
		]
		alert result
	][
		if find err/arg1 "Server error: HTTP/1.1 404 Not Found" [
			alert "You don't seem to be logged in .. check your credentials again"
		]
	]
]
revise-message: func [parent-id [integer!] message face
	/local err result
][
	result: err: none
	bind edit-url 'parent-id
	if error? err: try [
		result: to string! write rejoin edit-url compose/deep compose/deep copy/deep [
			POST
			[(header)]
			(rejoin ["text=" url-encode message "&fkey=" fkey])
		]
	][
		if find err/arg1 "Server error: HTTP/1.1 404 Not Found" [
			alert "You don't seem to be logged in .. check your credentials again"
		]
	]
	if result [
		either result = {"ok"} [
			set-face face copy ""
			update-face face
		][
			alert result
		]
	]
]

speak: func [message room-id /local err][
	if message = last-message [exit]
	if error? err: try [
		write chat-target-url room-id compose/deep compose/deep copy/deep [
			POST
			[(header)]
			(rejoin ["text=" url-encode message "&fkey=" fkey])
		]
	][
		?? err

		if find err/arg1 "Server error: HTTP/1.1 404 Not Found" [
			alert "You don't seem to be logged in .. check your credentials again"
		]
	]
]

read-messages: func [cnt room-id][
	probe compose/deep compose/deep copy/deep [
		POST
		[(header)]
		(rejoin ["since=0&mode=Messages&msgCount=" cnt "&fkey=" fkey])
	]
	to string! write read-target-url room-id compose/deep compose/deep copy/deep [
		POST
		[(header)]
		(rejoin ["since=0&mode=Messages&msgCount=" cnt "&fkey=" fkey])
	]
]
message-rule: [
	<event_type> set event_type integer! |
	<time_stamp> set timestamp integer! |
	<content> set content string! |
	<id> integer! |
	<user_id> set person-id integer! |
	<user_name> set user-name string! |
	<room_id> quote (room-id) |
	<room_name> string! |
	<message_id> set message-id integer! |
	<parent_id> set parent-id integer! |
	<show_parent> logic! |
	tag! skip |
	end
]

update-messages: func [room-id /local result
][
	;attempt [
	result: load-json/flat read-messages no-of-messages room-id
	?? result
	messages: result/2
	; now skip thru each message and see if any unread
	message-rule: compose copy message-rule

	foreach msg messages [
		content: user-name: none message-no: 0
		either attempt [parse msg [some message-rule]] [
			?? msg
			?? message-id
			if event_type = 3 [
				view compose [
					area (mold msg)
				]
			]

			if all [
				integer? message-id
				message-id > 0
				not exists? join storage-dir message-no
				any [event_type = 1 event_type = 2]
			][
				write join storage-dir message-no msg
			]
			attempt [content: trim decode-xml content]
			;; should this be inside the 'if ?
			if message-id > lastmessage-no [
				lastmessage-no: message-id
				repend/only u/all-messages [person-id message-id user-name content timestamp]
			]
		] [print "failed"]
	]
	;]
]


tool-bar-inf: now

;; got to save it sometime ...
either exists? %toolbar.r3 [
	print "loading images off disk"
	tool-bar-data: load %toolbar.r3
	tool-bar-inf: info? %toolbar.r3
	tool-bar-inf: tool-bar-inf/date
	?? tool-bar-inf
][
	print "loading images off web"
	tool-bar-data: grab-icons referrer-url room-id room-descriptor
	rsolog "now have the tool bar data"
	rsolog join "Length: " length? tool-bar-data
]

view [
	hpanel [
		vpanel [
			titletl: title "Room Name goes here and it might be quite long" 150
			message-table: text-table 200x400 ["Username" #3 150 "Chat" #4 900 "Time" #5 10]
			[] on-action [
				row: get-face face
				column: to integer! row/x
				row: to integer! row/y
				row-data: pick u/all-messages row
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
			content-bar: hpanel [
				; tb: tool-bar [] on-action [print arg]
			]
			hpanel 3 [
				head-bar "Bot Commands"
				head-bar "Chat Area"
				head-bar "Chat Functions"
				vpanel [

					bot-commands: text-table 200x100 ["Command" #1 40 "Purpose" #2 100]
					[
						["help" "returns a list of bot comands"]
						["delete" "deletes the last response made by bot"]
						["introduce me" "says something known about me stored on system"]
						["version" "current version of bot"]
						["cc nn" "Curecode ticket no to display"]
						["fetch nn" "Fetches stored JSON message by its ID"]
						["what is the meaning of life?" "Asks purpose of life"]
						["Greet" "Sends a greeting to the bot"]
						["Save my details url!" "Save my details as url with timezone"]
						["Search" "Search by key"]
						["Tweet" "Tweet as rebolbot"]
						["Show links by " "Show links by user"]
						["Shut Up" "Close bot down - emergency"]
						["Source" "Source of Rebol function"]
						["Save key [word! |string!] description url!" "Saves key, description and url"]
						["Remove key" "Removes named key"]
						["Find description" "Finds named key"]
						["What is the time in GMT?" "Time in GMT"]
						["Who do you know?" "Returns a list of known users"]
						["present?" "Who is currently online"]
						["Who is " "Who is the named user"]
					] on-action [
						switch cmd: pick get-face/field face 'row 1 [
							"Save my details url!" [
								cmd: copy ""
								view/modal [
									hpanel [
										vpanel [
											label "My Personal Details"
											label "URL: " urlfld: field 200 on-action [
												attempt [
													all [
														url: load get-face urlfld
														url! = type? url
														set 'cmd ajoin ["Save my details " url " " now/zone]
													]
												]
												close-window face
											]
										]
									]
									when [enter] on-action [focus urlfld]
								]
							]
							"Greet" [
								view/modal [
									text-list ["Hi" "Hello" "Goodbye" "morning" "afternoon" "evening" "night"] on-action [
										set 'cmd form pick pick get-face/field face 'table-data arg 1
										close-window face
									]
								]
							]
						]
						set-face chat-area ajoin ["@" get-face botbtn " " cmd]
						focus chat-area
					]
				]
				chat-area: area "" 600x90 options [min-hint: 750x50 detab: true]
				on-key [
					do-actor/style face 'on-key arg 'area
					if all [
						arg/key = #"^/"
						find arg/flags 'control
					][
						do-face sendbtn
					]


				]
				scroll-panel [
					htight 2 [
						time-fld: field ""
						update-fld: field ""
						sendbtn: button "SEND" on-action [
							use [txt] [
								txt: get-face chat-area
								if all [
									found? txt
									not empty? txt
								] [
									set-face chat-area copy ""
									if txt <> last-message [
										speak txt u/room-id
										set 'last-message txt
									]
								]
							]
							;= update toolbar
							comment {
                                        read the page and save it
                                        extract messages
                                        extract current users
                                        if current users <> last users [
                                            grab new images
                                        ] 
                                    }

							len: length? u/all-messages
							; clear u/all-messages
							print ["loading messages at " now]

							foreach msg read storage-dir [
								timestamp:
								person-id:
								message-id:
								parent-id: 0
								user-name: make string! 20

								message-rule: [
									<event_type> set event_type integer! |
									<time_stamp> set timestamp integer! |
									<content> set content string! |
									<id> integer! |
									<user_id> set person-id integer! |
									<user_name> set user-name string! |
									<room_id> quote (room-id) |
									<room_name> string! |
									<message_id> set message-id integer! |
									<parent_id> set parent-id integer! |
									<show_parent> logic! |
									tag! skip |
									end
								]

								if not dir? msg [
									if error? try [
										msg: load join storage-dir msg
									][
										msg: to string! read join storage-dir msg
										either parse msg [thru <content> insert {"} to " <" insert {"} thru <user_name> insert {"} to " <" insert {"} to end][
											attempt [msg: load msg]
										][
											msg: copy []
										]
									]
									content: none
									user-name: none
									message-id: 0
									message-rule: compose copy message-rule
									rsolog "parsing msg"
									either attempt [parse msg [some message-rule]] [

										attempt [content: trim decode-xml content]
										; ?? message-id
										if event_type = 3 [
											view compose [
												area (mold msg)
											]
										]

										if all [
											message-id > lastmessage-no
											any [event_type = 1 event_type = 2]
											;; event_type 2 is edit .. so need to find and replace existing message in display
										][
											set 'lastmessage-no message-id
											repend/only u/all-messages [person-id message-id user-name content timestamp]
										]
									] [print ["failed parse" msg]]
								]
							]


							data: copy/deep u/all-messages
							foreach msg data [
								msg/5: from-now utc-to-local unix-to-utc msg/5
							]

							SET-FACE/FIELD window-message-table data 'data
							set-face window-update-fld form now/time

							?? len
							probe length? u/all-messages

							if all [
								value? 'len
								integer? len
								len <> length? u/all-messages
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

						botbtn: button "RebolBot" on-action [
							set-face chat-area join "@rebolbot " get-face chat-area
							focus chat-area
						]

						toggle "Fetch Msgs" green on-action [
							forever [
								if not get-face face [
									clear-content content-bar
									exit
								]
								rsolog "update-messages"
								if error? err: try [
									; grabs latest messages and saves to message store, as well as all-messages user global
									update-messages u/room-id
								][
									print mold err
								]
								; update-icons referrer-url
								data: copy/deep u/all-messages
								rsolog "update times on text-table data"
								foreach msg data [
									msg/5: from-now utc-to-local unix-to-utc msg/5
								]
								rsolog "update update-fld with time"
								set-face update-fld form now
								rsolog "update message-table"
								SET-FACE/FIELD message-table data 'data
								rsolog "update scroller"
								set-face message-table/names/scr 100%
								rsolog "waiting..."
								wait wait-period
								;; update toolbar
								rsolog "checking tool-bar data"
								new-tool-bar-data: update-icons u/referrer-url u/room-id u/room-descriptor
								rsolog type? new-tool-bar-data
								rsolog join "Length of toolbar data: " length? new-tool-bar-data
								rsolog "obtained new tool bar data"
								;view [
								;         tool-bar new-tool-bar-data on-action [print arg]
								;]
								; set-face statusfld rsolog "check for changes in tool-bar"
								if not equal? new-tool-bar-data u/tool-bar-data [
									u/tool-bar-data: new-tool-bar-data
									clear-content content-bar
									rsolog "appending new tool bar layout"
									; set-face statusfld "Changing toolbar"
									append-content content-bar [tb: tool-bar u/tool-bar-data on-action [print arg]]
									; set-face chat-area join get-face chat-area " .. updated toolbar"
									show-now [chat-area content-bar]
								]
							]
						]

						button "Code" brown on-action [
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
						button "Delete Message" red on-action [
							parent-id: none
							if all [
								parse get-face chat-area [":" copy parent-id to end]
								trim parent-id
								attempt [parent-id: load parent-id]
								integer? parent-id
							][
								delete-message parent-id
								set-face chat-area copy ""
							]
						]

						button "Revise Message" on-action [
							parent-id: none
							if all [
								parse get-face chat-area [":" copy parent-id thru " " copy msg to end]
								trim parent-id
								attempt [parent-id: load parent-id]
								integer? parent-id
							][
								revise-message parent-id msg chat-area
							]
						]


						button "Halt" red on-action [
							close-window face
							halt
						]
						button "Settings" on-action [
							view [
								vpanel [
									title "Settings"
									hpanel [
										label "Initial Fetch" init-fetchfld: field 30
										label "Poll Fetch no: " nom-fld: field 30 on-action [
											attempt [
												set 'no-of-messages to integer! arg
												close-window face
											]
										]
										label "Poll Period (sec)" pollfld: field 30
									]
									hpanel [
										button "Cancel" red on-action [close-window face]
									]
									bar
									hpanel 2 [
										label "fkey" fk-fld: field
										label "USR cookie" cookie-area: field
										label "Chat room ID" room-id-fld: field
										label "Chat descriptor" descriptorfld: field
									] options [black border-size: [1x1 1x1]]
									button "Save Config" on-action [
										tobj: make object! [fkey: bot-cookie: room-id: room-descriptor: none]
										tobj/fkey: get-face fk-fld
										tobj/bot-cookie: trim/head/tail get-face cookie-area
										attempt [tobj/room-id: to-integer get-face room-id-fld]
										tobj/room-descriptor: get-face descriptorfld
										; check for the appropriate values in the object!
										if not parse tobj/bot-cookie ["usr=t=" to end][
											alert "usr cookie needed of form: usr=t=xxxxx&s=xxxxx"
											exit
										]
										foreach [key type][
											fkey string!
											room-id integer!
											room-descriptor string!
											bot-cookie string!
										][
											if not-equal? type to word! t: type? tobj/(key) [
												alert ajoin ["Wrong value for " form key " expected " type " and got " t]
												exit
											]
										]
										save %rsoconfig.r3 tobj
										close-window face
										foreach key words-of tobj [
											u/(key): tobj/(key)
										]
										set-face titletl u/room-descriptor
										show-now titletl
										; clear out the old messages
										u/all-messages: copy []
										SET-FACE/FIELD window-message-table copy [] 'data
										show-now [window-message-table]
										u/lastmessage-no: 0
										update-messages u/room-id

									]
									when [enter] on-action [
										set-face nom-fld no-of-messages
										set-face fk-fld u/fkey
										set-face cookie-area u/bot-cookie
										set-face room-id-fld u/room-id
										set-face descriptorfld u/room-descriptor
									]
								]
							]
						]
					]
				]
			] options [min-hint: 1200x150 max-hint: 1400x200]
		]

		when [enter] on-action [
			set 'window-update-fld update-fld
			set 'window-message-table message-table
			set 'mychat-area chat-area
			set-face time-fld join "Session from: " now/time
			show-now time-fld
			set-face titletl u/room-descriptor
			append-content content-bar [tb: tool-bar u/tool-bar-data on-action [print arg]]
		]
	]
]


