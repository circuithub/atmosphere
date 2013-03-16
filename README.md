atmosphere
==========

Background tasking for CircuitHub (current RabbitMQ backed)

# Usage

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