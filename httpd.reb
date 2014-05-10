REBOL [
	title: "SO chat classifier"
	file: %httpd.reb
	author: [abolka "Graham Chiu"]
	date: [4-Nov-2009 10-May-2014]
	version: 0.0.3
]

do http://reb4.me/r3/altwebform.r
import http://reb4.me/r3/altjson.r

so-db: [
	admin [
		"GrahamChiu" ["password"]
		"earl" ["password "]
		"johnk" ["password"]
		"rgchris" ["password"]
	]
	"rebol3" [
		1 2 3
	]
	"red" [
		4 5 6
	]
	"r3gui" [
		7 8 9
	]
	"general" [
		10 11 12
	]
]

if exists? %so-db.reb [
	so-db: load %so-db.reb
]

save-db: does [save %so-db.reb so-db]

remove-key: funct [key so-db][
	foreach [class db] next next so-db [
		if at: find db key [remove at]
	]
]
code-map: make map! [200 "OK" 400 "Forbidden" 404 "Not Found"]
mime-map: make map! ["html" "text/html" "jpg" "image/jpeg" "r" "text/plain"]
error-template: {
    <html><head><title>$code $text</title></head><body><h1>$text</h1>
    <p>Requested URI: <code>$uri</code></p><hr><i>shttpd.r</i> on
    <a href="http://www.rebol.com/rebol3/">REBOL 3</a> $r3</body></html>
}

error-response: func [code uri /local values] [
	values: [code (code) text (code-map/:code) uri (uri) r3 (system/version)]
	reduce [code "text/html" reword error-template compose values]
]

send-response: func [port res /local code text type body] [
	set [code type body] res
	write port ajoin ["HTTP/1.0 " code " " code-map/:code crlf]
	write port ajoin ["Content-type: " type crlf crlf]
	write port body
]

separator: "^/^/"
handle-request: func [config req
	/local uri data result outer db admin-db user-data start finish class verb
] [
	print ["Request is: " to string! req]
	data: {"notok - default fall thru"}
	either parse to string! req [
		copy verb to space space [
			copy uri to space if (remove uri equal? verb "GET") to end
			|
			thru separator copy URI to end
		]
	][
		print "parsed request okay"
		?? uri
		either error? try [
			uri: load-webform uri
		][
			data: {"notok - faulty parameters"}
		][
			?? URI
			?? verb
			switch/default verb [
				"GET" [
					; gets from start to end of result
					class: none
					either parse URI [
						some [
							'class set class string!
							|
							'start set start string! (start: attempt [to integer! start])
							|
							'end set finish string! (finish: attempt [to integer! finish])
						]
					][
						; if class is none, assume search all groups
						either not all [start finish][
							data: {"notoky-no start or end"}
						][
							set [start finish] sort reduce [start finish]
							either class [
								; named class
								either db: select so-db class [
									result: collect [
										foreach id db [
											if all [
												id >= start
												id <= finish
											][
												keep id
											]
										]

									]
									data: to-json append/only copy reduce [class] result
								][
									; class does not exist
									data: {"notok - noexistent class"}
								]
							][
								outer: copy []

								foreach [class db] next next so-db [
									result: collect [
										foreach id db [
											if all [
												id >= start
												id <= finish
											][
												keep id
											]
										]
									]
									if not empty? result [
										append outer class
										append/only outer result
									]
								]
								probe outer
								data: to-json outer
							]
						][; didn't parse the GET URI
							data: {"notok - no parse GET uri"}
						]
					][
						data: {"notok - not parsing outer URI"}
					]
				]

				"DELETE" [; DELETE "user=Graham&password=xyz&start=n&end=n"
					print "entered DELETE"
					user: password: start: finish: none
					either parse URI [
						some [
							'user set user string!
							|
							'password set password string!
							|
							'start set start string! (start: attempt [to integer! start])
							|
							'end set finish string! (finish: attempt [to integer! finish])
						]
					][
						print "parsed DELETE url okay"
						either all [
							user password start finish
						][; now to check if authorised
							admin-db: select so-db 'admin
							either user-data: select admin-db user [
								print "found user"
								?? user-data
								either user-data/1 = password [
									print "user passsword is okay"
									; authorised - found user and password matches
									set [start finish] sort reduce [start finish]
									; now start deleting all keys.  Might be duplicates so go thru all groups
									until [
										remove-key start so-db
										++ start
										start > finish
									]
									save-db
									data: {"ok"}
								][
									data: {"notok - not authorised"}
								]
							][
								data: {"notok - not authorised"}
							]
						][
							data: {"notok - not all params supplied to DELETE"}
						]
					][
						data: {"notok - not parse PUT rule"}
					]
				]

				"PUT" [
					print "entered PUT"
					either parse URI [
						some [
							'class set class string!
							|
							'start set start string! (start: attempt [to integer! start])
							|
							'end set finish string! (finish: attempt [to integer! finish])
						]
					][
						print "parsed PUT url okay"
						either all [
							class start finish
						][
							either db: select so-db class [
								set [start finish] sort reduce [start finish]
								until [
									append db start
									++ start
									start > finish
								]
								save-db
								data: {"ok"}
							][
								data: {"notok - unknown class"}
							]
						][
							data: {"notok - not all params supplied to PUT"}
						]
					][
						data: {"notok - not parse PUT rule"}
					]
				]

				"POST" [
					data: {"notok - currently not supported"}
				]
			][
				data: {"notok - unrecognised html verb"}
			]
		]
	][
		print "failed to parse req"
		data: {"notok - failed to parse request"}
	]
	reduce [200 "text/plain" data]
]

awake-client: func [event /local port res] [
	port: event/port
	switch event/type [
		read [
			either find port/data to-binary join crlf crlf [
				res: handle-request port/locals/config port/data
				send-response port res
			] [
				read port
			]
		]
		wrote [close port]
		close [close port]
	]
]
awake-server: func [event /local client] [
	if event/type = 'accept [
		client: first event/port
		client/awake: :awake-client
		read client
	]
]


serve: func [web-port web-root /local listen-port] [
	print ajoin ["Serving on local port " web-port " at " what-dir]
	listen-port: open join tcp://: web-port
	listen-port/locals: construct compose/deep [config: [root: (web-root)]]
	listen-port/awake: :awake-server
	wait listen-port
]

serve 8080 system/options/path
halt

