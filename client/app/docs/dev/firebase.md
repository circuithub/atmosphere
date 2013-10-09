# Job flow 

### Submit Job

The ```rainMaker``` writes actual job data to ```rainDrops```:

```
/atmosphere
  /rainDrops
    /<key>
      /data
      /job
      /log
      /result
```

The ```rainMaker``` writes the flag to ```sky```

```
/atmosphere
  /sky
    /todo
      /<key> : true
```

### Schedule Job

The ```Sky``` detects the write to ```sky/todo```

### Perform Job

### Error Handling

### Chaining of Jobs

### Recovery