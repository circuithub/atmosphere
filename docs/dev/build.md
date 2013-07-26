# Website Build System

Weather Station's website is built using:

* jade -- compiles to HTML
* stylus -- compiles to CSS
* coffee-script -- compiles to javascript

The site is organized around the component model where files are grouped by function rather than by file type.

For example, all of the files in a graphing widget would be located under ```/client/app/graph```

All files should be located under ```/client/app/``` are monitored by the build system for any changes. You should not have to restart the server to see changes propagate. This makes development of new functionality easier.

## Javascript

### Vendor code

place all vendor modules in /client/vendor
npm module coffee-toaster is applied as middleware to watch to the /client/app

## Markup

## Styling

Due to limitations in the stylus middleware's watching ability, all stylus files must be referenced (imported) into ```/client/app/stylesheets/app.styl```.

Place your Stylus file in the appropriate component directory and add an import statement for it in ```app.styl```.

## Routing

Routes are handled here: ```/server/routes/index.coffee```