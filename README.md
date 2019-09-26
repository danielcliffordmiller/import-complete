import-complete
===============

Just an initial commit.

Two files here, a perl script to create a tag file that is
a JSON matching simple class names to a list of packges.

For example:
```
{ "Stream": [ "java.util.stream" ] }
```
That file is then sourced by the vimscript file which maps
your leader key followed by `i` to open a menu for the class
name under the cursor.

Also yes, this is a very rough project, still more work to be done.
