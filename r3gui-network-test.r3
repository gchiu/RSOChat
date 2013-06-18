Rebol [
	file: %r3gui-network-test.r3
	notes: {
		to test async networking with the r3gui
		code taken from earl's http server
		
		At present, the faces are updated using 'show-now as there are issues with the styles
		which should update with the normal set-face command
		
		From rebol2
		
		rebol [ 
			file: %test-r3.r
		]
		p: open/direct/lines tcp://localhost:8000
		insert p {hello world again^/}
		pick p 1
		insert p {a second test^/}
		pick p 1
		close p
	}
	author: "Graham Chiu"
	Date: 18-June-2013
	version: 0.0.2
]

load-gui

window-inputarea: none

awake-client: func [event /local port msg ][
    port: event/port
    print [ "received event of " event/type ]
    switch/default event/type [
        read [ 
			msg: to string! port/data 
			set-face window-inputarea msg
			; AREA is not updating visually during ON-SET. This is workaround for now.
			SET-FACE/FIELD window-tt [ [ "Earl" "Should work now" 11:00 ]] 'data
			show-now [ window-tt window-inputarea  ]

			print [ "Sent to inputarea: " msg ]
			write port to binary! join "ACK" newline
			false 
		]
        close [ close port true ]
        error [ close port true ]
        wrote [ read port false ]    
    ][ false ]
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
     print [ "listening on port .. " web-port " and r3gui window" ]
]

view [ 
  vpanel [
	title "test window" 
	vpanel [
		text "you can resize me while I'm waiting"
		tt: text-table 100x40 ["Username" #1 100 "Chat" #2 100 "Time" #3 10]
		[
			[ "Graham" "hello world" 8:00 ]
		] on-action [ print [ "you clicked on me at " arg ] ]
		inputarea: area
		hpanel [
			button "Clear" on-action [ set-face inputarea "" ]
			button "Halt" red on-action [ close-window face halt ]
		]
	] options [ max-hint: 300x200 ]
  ]
  when [enter] on-action [
	set 'window-inputarea inputarea
	set 'window-tt tt
	serve 8000
  ]
]
