Rebol [
	Title: "RSO Chat Modules"
	Date: 1-May-2014
	Author: "Christopher Ross-Gill"
]

logfile: %events.reb
if not exists? logfile [write logfile ""]
debug: true

do rsolog: func [event][
	if debug [
		print ["logging event" event]
		write/append logfile join reform [now/time event] newline
	]
]

foreach [module test][
	%r3-gui.r3 to-text
	%altjson.r3 load-json
	%altxml.r3 load-xml
	%altwebform.r load-webform
	%prot-http.r3 idate-to-idate
][
	unless value? :test [
		unless exists? module [
			rsolog join "fetching " module

			switch/default module [
				%r3-gui.r3 [
					test: body-of :load-gui
					either parse url [thru 'try set test block! to end][
						parse test [word! set test url!]
						write module read test
						do module
					][
						load-gui
					]
				]

				%altwebform.r  [
					write module read join http://reb4.me/r3/ module
				]

				%prot-http.r3 [
					write module read join https://raw.githubusercontent.com/gchiu/Rebol3/master/protocols/ module
				]
			][
				write module read join https://raw.githubusercontent.com/gchiu/RSOChat/master/ module
			]
		]

		do module
	]
]
