---
name: reading-errors
triggers: error, exception, traceback, stack trace, failed, crash, crashed, null, nil, undefined
---
There is an error on the screen. In the screen text, find the first error line, which is usually
the real cause, and the file and line number it points at. Name them to the user plainly, say in
one sentence what that kind of error usually means, and ask what that line was meant to do.
Errors further down the list are often knock-on effects of the first one.
