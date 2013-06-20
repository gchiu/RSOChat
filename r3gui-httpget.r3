rebol [
	title: "GUI & Async HTTP Demo" 
	author: [ 'abolka 'cyphre ]
	date: 2013-06-18
	notes: {
		appears to show multiple downloads occurring concurrently
	}
]

load-gui

log: copy ""

td-1: none

do-download: closure [url-field content-area /local url port prg progress-bar]  [
	prg: 0
    url: to-url get-face url-field
    port: make port! url
    port/awake: funct [event] [
        switch event/type [
            connect [
                ;; Use HTTP's READ actor to send the HTTP request once we are
                ;; connected.
				append-content progress-panel [progress 1x1]
				set 'progress-bar last faces? progress-panel
				append log rejoin [now/precise/time " Started download of: " url newline]
				set-face content-area log
                read event/port
            ]
            read [
                ;; Schedule the low-level TCP port for further reading.
                ;; (@@ Smells! Should be taken care of by the HTTP scheme.)
				;sice we don't know the total data size we are cheating a bit here ;)
				set-face progress-bar set 'prg prg + (1 - prg / 50)
                read event/port/state/connection
            ]
            done [
				remove-content/pos progress-panel progress-bar
				show-now progress-panel
                ;; Use HTTP's COPY actor to read the full website content once
                ;; reading is finished.
				append log rejoin [now/precise/time " Finished download of: " url newline]
                set-face content-area log
                close event/port
                return true
            ]
        ]
        false
    ]
    open port
	; wait port
]

view [
    vpanel [
        title "Async HTTP GUI Demo"
        hpanel [
            text "URL"
            url-field: field ; "http://www.rebol.com/index.html"
			"http://rebolsource.net/downloads/win32-x86/r3-gfc51038.exe"
        ]
		hpanel [
			progress-panel: vpanel [head-bar "Progress" options [min-size: 220x20 max-size: 220x20]]
			content-area: area options [min-hint: 'init ]
		]
        hpanel [
            button "Download" on-action [
				do-download url-field content-area
                set 'td-1 set-timer/repeat [
					print [ "fetching .." now ]
					do-download url-field content-area
				] 1.0
            ]
            button "Quit" on-action [
				close-window face
				halt
            ]
        ]
    ]
]