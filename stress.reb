Rebol [
	Title: "Stress the Chat classifier"
	File: %stress.reb
	Date: 11-May-2014 
	Author: "Graham Chiu"
	Purpose: {
		to test the SO chat classifier server
	}
]

server: http://localhost:8080

print "Getting all groups"
result: to string! read server
?? result

print "Getting a range of values"
result: to string! read join server "?class=r3gui&start=5&end=1000"
?? result

print "Getting a range of values with reversed start and end"
result: to string! read join server "?class=r3gui&start=100&end=5"
?? result

print "Adding values into a group"
result: to string! write server [ PUT "class=r3gui&start=13&end=20" ]
?? result

print "Getting all of one group"
result: to string! read join server "?class=r3gui"
?? result

print "Deleting values with incorrect authentication"
result: to string! write server [ DELETE "user=Graham&password=password&start=13&end=20" ]
?? result

print "Deleting values using correct authentication"
result: to string! write server [ DELETE "user=GrahamChiu&password=password&start=13&end=20" ]
?? result

print "Getting a range of values just deleted"
result: to string! read join server "?class=r3gui&start=13&end=20"
?? result

print "POST not supported yet"
result: to string! write server [ POST "add=test" ]
?? result

halt
