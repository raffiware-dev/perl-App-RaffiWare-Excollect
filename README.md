# exc - ExCollect Client

---

*exc* is the command line client for the ExCollect service API.  It is responsible for managing the process daemon that
will poll for and execute commands dispatched through ExCollect.


```
  exc client-init $ACTIVATION_TOKEN
  exc watcher start 

```


## Installing 

```
   perl Makefile.PL
   make
   make test
   make install 
```

## Configuration 

*exc* client configuration is stored in the following file:

~/.exc/exc.cfg
