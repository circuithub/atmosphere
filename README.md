```
 _______ _______ _______  _____  _______  _____  _     _ _______  ______ _______
 |_____|    |    |  |  | |     | |______ |_____] |_____| |______ |_____/ |______
 |     |    |    |  |  | |_____| ______| |       |     | |______ |    \_ |______

```
Robust RPC/Jobs Queue for Node.JS Web Apps Backed By RabbitMQ

# Usage

## Initialize (Connect to Server)

```coffeescript
#Init Cloud (Worker Server -- ex. EDA Server)
atmosphere.init.rainCloud jobTypes, (err) ->
```
  
```coffeescript
#Init Rainmaker (App Server)
atmosphere.init.rainMaker (err) ->
```

## Submit a Job

### Example Response

Message:
```json
{ data: <Buffer 48 65 6c 6c 6f 20 57 6f 72 6c 64 21>,
  contentType: 'application/octet-stream' } 
```

Headers:
```json
{}
```

deliveryInfo:
```json
{ contentType: 'application/octet-stream',
  queue: 'testQ',
  deliveryTag: 1,
  redelivered: false,
  exchange: '',
  routingKey: 'testQ',
  consumerTag: 'node-amqp-19144-0.19309696881100535' }
```