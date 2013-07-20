```
 _______ _______ _______  _____  _______  _____  _     _ _______  ______ _______
 |_____|    |    |  |  | |     | |______ |_____] |_____| |______ |_____/ |______
 |     |    |    |  |  | |_____| ______| |       |     | |______ |    \_ |______

```
Flexible Robust RPC/Jobs Queue for Node.JS Web Apps Backed By [Firebase](http://firebase.com)

# Features

* Robust: timeouts, retries, error-handling, auto-reconnect, etc
* Flexible: Supports multiple job queueing models
* Efficient: thin, early release of resources
* Scales: RPC and Task sub-division allows jobs to be spread across mulitple CPUs
* "Fixes" Heroku Routing: You control how and when Atmosphere distributes work
* Proven: Backed by Firebase, used in production

# Usage Model

Atmosphere is a flexible jobs queue. It can support three basic use cases:

1. Simple Remote Procedure Call (S-RPC) -- A job is submitted, executed by one of several remote listening workers, and a callback function is invoked when the work is complete or the timeout expires.
2. Complex Remote Procedure Call (C-RPC) -- A chain of jobs are submitted and execution in sequence is desired. Data is passed from one job to the next. The callback may be invoked at any specified point along the chain... or at the end if unspecified.
3. Message Passing for Logging (MP-L) -- A job is submitted with no expectation for a response. Used for monitoring/logging applications.

# Jobs Model

Externally, a job looks like this:

```coffeescript
	job = 
		type: "remoteFunction" #the job type/queue name
		name: "special job" #name for this job
		data: {msg: "useful"} #arbitrary serializable object
		timeout: 30 #seconds
```

It has...

* a category (or "type") -- internally, this is the name of the queue in the RabbitMQ dashboard 
* a name -- this is a descriptor for the work within the category, for example {type:"syncUser", name: "user1"}
* data -- this is optional and arbitrary. It is passed to the function actually doing the work on the ```rainCloud```.
* a timeout -- After this many seconds, if a response from the completed job hasn't been received, an error will be sent to the calling function on the ```rainMaker```. However, the job will still proceed to completion on the ```rainCloud```. This is useful for situations where the ```rainCloud's``` get busy and you want to inform your user of the ongoing delay. Only one response is ever sent per job so a side-channel (usually a database) must be used to indicate work completion after that point.


# Routing Model

Atmosphere consists of two entities: ```rainMaker``` and ```rainCloud```

* ```rainMakers``` dance to make it rain -- they submit jobs because they want work done.
* ```rainClouds``` actually release water -- they perform the work because a job was received.

You can control how work is distributed in the atmosphere by understanding the routing rules:

1. ```rainClouds``` register for the job types they want to handle by specifying which types and which functions should be invoked when work is received for that job type.
2. Atmosphere distributes jobs among all ```rainClouds``` registered for that job in a round-robin fashion (least recently tasked gets the next job). 
3. ```rainClouds``` can only process one job *of each job type* at a time. If you have I/O intensive tasks this works extremely well. If you have compute intensive tasks this does not. See the section at the end on compute intensive tasking to learn how to employ atmosphere effectively with CPU-heavy workloads.
4. Atmosphere does not distribute jobs to busy ```rainClouds```. A cloud is busy if it is currently processing a job of the *same type* as the job trying to be scheduled.
5. If a ```rainCloud``` crashes or is shutdown, any tasks that have not yet completed are re-queued and go the next available cloud following the rules above. This happens automatically (no action is necessary on the part of the developer).



# Installation & Usage

Atmosphere is tested and supported in node.js v.0.10.8 and above.

```npm install atmosphere```

## Configuration

(TODO: Add Firebase and GitHub setup instructions)

# Monitoring

The Atmosphere monitoring GUI (Weather Station) is available, by default, at: http://localhost:3000/


# Hello World!

Welcome to life in an atmosphere... breathe in... breathe out... =)

Let's use our job queue to do some simple remote-procedure-call-style work. We submit a job and print out the result when it's done. 

Atmosphere looks and behaves like any other locally executing node.js asynchronous function, but the work is being done on one of many remote servers or local cores.

### Local (makes request)
```coffeescript
#[1.] Include Module
atmosphere = require("atmosphere").rainMaker # <-- Notice this!

#[2.] Connect to Atmosphere
atmosphere.init "requester", (err) ->
	# Check for initialization errors
	return err if err?

	#[3.] Submit job
	job = 
		type: "example" #the job type (queue name)
		name: "my first atmosphere job" #name for this work request (passed to remote router)
		data: {msg1: "Hello", msg2: "World!"} #arbitrary serializable object to pass to remote
		timeout: 30 #seconds (if timeout elapses, error response is returned to callback)
	atmosphere.submit job, (error, data) ->

		#[4.] Job is complete!
		return error if error?			
		console.log "RPC completed and returned:", data
```

### Remote (fulfills request)
```coffeescript
#[1.] Include Module
atmosphere = require("atmosphere").rainCloud #<-- Notice this!

#[2.] Local Function to Execute (called remotely)
localFunction = (ticket, data) ->
	console.log "Working on job with data: #{data.msg1} #{data.msg2}"
	error = undefined
	results = "This string was generated inside the work function"
	atmosphere.doneWith(ticket, error, results)

#[3.] Which possible jobs should this server register to handle?
handleJobs = 
	remoteFunction: localFunction #object key must match job.type

#[4.] Connect to Atmosphere
atmosphere.init "responder", (err) ->
	# Check for errors
	return err if err?
	#All set now we're waiting for jobs to arrive
```


# Usage Models



## RPC (Simple Job Queue)

### Local (makes request)
```coffeescript
#Include Module
atmosphere = require("atmosphere").rainMaker

#Connect to Atmosphere
atmosphere.init "requester", (err) ->
	# Check for errors
	if err?
		console.log "Could not initialize.", err
		return
	# Submit job (make the remote procedure call)
	job = 
		type: "remoteFunction" #the job type/queue name
		name: "special job" #name for this work request (passed to remote router)
		data: {msg: "useful"} #arbitrary serializable object to pass to remote function
		timeout: 30 #seconds
	atmosphere.submit job, (error, data) ->
		if error?
			console.log "Error occurred executing function.", error
			return
		console.log "RPC completed and returned:", data
```

### Remote (fulfills request)
```coffeescript
#Include Module
atmosphere = require("atmosphere").rainCloud

#Local Function to Execute (called remotely)
# -- ticket = {type, name, id}
# -- data = copy of data object passed to submit
localFunction = (ticket, data) ->
	console.log "Doing #{data.msg} work here!"
	error = undefined
	results = "This string was generated inside the work function"
	atmosphere.doneWith(ticket, error, results)

#Which possible jobs should this server register to handle
handleJobs = 
	remoteFunction: localFunction #object key must match job.type

#Connect to Atmosphere
atmosphere.init "responder", (err) ->
	# Check for errors
	if err?
		console.log "Could not initialize.", err
		return
	#All set now we're waiting for jobs to arrive
```




## Sub-Dividing Complex Jobs (Chaining Jobs)

#### Behavior Summary

* If prior job finishes with error object defined, callback is made immediately
* If prior job finishes without error, data object is passed to next job
* Callback can be forced on success, but chain execution will continue
* Only one callback per chain

#### Specification of Subsequent Jobs

* Subsequent jobs do not specify a job name -- same name is used throughout chain
* Subsequent jobs do not specify a timeout -- timing begins from submission of job chain

#### Data Cascade

Data is passed between jobs by merging the data object specified in the job description in the job chain with the data object resulting from the execution of the previous job.

Here is an example job chain:

```coffeescript
job1 = 
	type: "first" #the job type/queue name
    name: "job1" #name for this job
    data: {param1: "initial message"}
    timeout: 5 #seconds
job2 = 
	type: "second"
	data: {param2: "initial message"}
jobChain = [job1, job2]
```

1. When ```job1``` executes, ```data = {param1: "initial message"}```

2. Let's say that ```job1``` finishes by calling ```doneWith(..)``` using the following:

```coffeescript
doneWith ticket, undefined, {a: 1, b: 2, c: 3}
```

3. When ```job2``` executes, ```data = { param2: "initial message", first: {a: 1, b: 2, c: 3} }```

Notice that the job's data object is extended by an additional key equal to the job type of the previous job in the chain.

In this way, you can ensure that the data you rely on came from the proper context. 

Atmosphere only keeps track of the data between successive jobs, but you can easily extend this by passing results through. Simply call ```doneWith``` with the same data object as was passed in and extend it with your additonal results.

#### Usage

First, you must connect to atmosphere to submit jobs:

```coffeescript
#Include Module
atmosphere = require("atmosphere").rainMaker

#Connect to Atmosphere
atmosphere.init "requester", (err) ->
	# Check for errors
	if err?
		console.log "Could not initialize.", err
		return
	# Submit job (make the remote procedure call)
```

### Submit a Job --> Job --> Callback

* Jobs are daisy chained -- one job is run after the other completes
* If the first jobs returns an error, the second is not processed
* Results from the first job are merged with the second jobs data parameter before execution so that data cascades between jobs
* Unlimited jobs many be chained in this fashion.

```coffeescript
	job1 = 
		type: "remoteFunction" #the job type/queue name
		name: "special job" #name for this job
		data: {msg: "useful"} #arbitrary serializable object
		timeout: 30 #seconds
	job2 = 
		type: "remoteFunction"
		data: {param2: "abc"} #merged with results from job1
	atmosphere.submit [job1, job2], (error, data) ->
		if error?
			console.log "Error occurred executing function.", error
			return
		console.log "RPC completed and returned:", data
```

### Submit a Job --> Callback --> Job

The callback is returned after job1 completes, but execution will continue to job2 if no error occurred. The callback from job2 (and subsequent) will be ignored.

```coffeescript
	job1 = 
		type: "remoteFunction" #the job type/queue name
		name: "special job" #name for this job
		data: {msg: "useful"} #arbitrary serializable object
		timeout: 30 #seconds
		callback: true
	job2 = 
		type: "remoteFunction"
		data: {param2: "abc"} #merged with results from job1
	atmosphere.submit [job1, job2], (error, data) ->
		if error?
			console.log "Error occurred executing function.", error
			return
		console.log "RPC completed and returned:", data
```

### Submit a Job --> Job (fire-and-forget)

A fire-and-forget job is one that, once submitted, will not invoke a callback. This is useful for jobs that serve only as dispatchers for routine maintenance (fanout directors) or jobs performing final logging (where additional recovery is not possible). 

You could, of course, use the normal callback syntax and simply ignore (empty function) the callback, but this will result in futher state management, tracking, and logged error messages (from the timeout if it occurs).

* Most efficient way to ignore a callback (reduces memory allocation and log noise)
* Execution will continue to job2 if no error occurred. 
* Errors that occur will be reported to the console, but otherwise ignored.

```coffeescript
	job1 = 
		type: "remoteFunction" #the job type/queue name
		name: "special job" #name for this job
		data: {msg: "useful"} #arbitrary serializable object
		timeout: 30 #seconds		
	job2 = 
		type: "remoteFunction"
		data: {param2: "abc"} #merged with results from job1
	atmosphere.submit [job1, job2], undefined # <-- NOTE THIS!
```

## Logging/Monitoring



# Stuff

From original code file:
1. worker functions in rain cloud apps get called like this:
  your_function(ticket, jobData)
2. When done, call doneWith(..) and give the ticket back along with any response data (must serialize to JSON)...
  atmosphere.thunder ticket, responseData
  
## Initialize (Connect to Server)

```coffeescript
#Init Cloud (Worker Server -- ex. EDA Server)
atmosphere.init.rainCloud jobTypes, (err) ->
```
  
```coffeescript
#Init Rainmaker (App Server)
atmosphere.init.rainMaker (err) ->
```



# Architecture
```coffeescript
rainMaker.submit(job, callback)
	--> RabbitMQ -->
		rainCloud.lightning(..)
			envelope
				external.function(ticket, data)
			envelope
		rainCloud.doneWith(..)
	<-- RabbitMQ <--
callback(errors, data)
```


# Data Structures & Formats

## External

### Current Job State

```coffeescript
    message = {data: {}, next: [job2, job3, job4, ...]}
```

### Job Ticket

```coffeescript
ticket = 
    type: deliveryInfo.queue
    name: headers.job.name
    id: headers.job.id
```

## Internal 

### jobChain (payload.next)

```
next = [
	{
		type: "remoteFunction" #the job type/queue name
		name: "special job" #name for this job
		data: {msg: "useful"} #arbitrary serializable object
		timeout: 30 #seconds
		callback: true #optional
	},
	{
		type: "remoteFunction" #the job type/queue name
		name: "special job" #name for this job
		data: {msg: "useful"} #arbitrary serializable object
		timeout: 30 #seconds
		callback: false #optional
	}
]
```

### rainMaker: Current Jobs (jobs)
```coffeescript
jobs[job.id] = 
	type: job.type
	name: job.name
	timeout: job.timeout
	callback: cbJobDone
```


### rainCloud: Current Jobs (currentJob)

```coffeescript
currentJob[deliveryInfo.queue] = {
    type: deliveryInfo.queue
    job: {name:, id:}    
    returnQueue: headers.returnQueue
    next: message.next
}
```

### Firebase Notes

*. Writing an empty object, ```{}```, deletes the current location

