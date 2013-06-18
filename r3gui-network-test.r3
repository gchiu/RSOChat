Rebol [
	file: %r3gui-network-test.r3
	notes: {
		to test async networking with the r3gui
		code taken from earl's http server
		
		The input area does not update until a windows event is received such as a mouse over
		
		From rebol2
		
		p: open/direct/lines tcp://localhost:8000
		insert p {hello world again^/}
		close p
	}
	author: "Graham Chiu"
	Date: 18-June-2013
	version: 0.0.1
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
			print [ "Sent to inputarea: " msg ]
			false 
		]
        close [ close port true ]
        error [ close port true ]
        wrote [ false ]    
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

serve: func [web-port window /local listen-port] [
    listen-port: open join tcp://: web-port
     listen-port/awake: :awake-server
     print [ "listening on port .. " web-port " and r3gui window" ]
    wait [ listen-port window ]
]

window: view/no-wait [ 
  vpanel [
	title "test window" 
	vpanel [
		text "you can resize me while I'm waiting"
		text-table 100x40 ["Username" #1 100 "Chat" #2 100 "Time" #3 10]
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
  when [load] on-action [ set 'window-inputarea inputarea]
]

serve 8000 window