Use only for a condition the user must know about for as long as it lasts — never as a transient notification (AeroSpork has no toasts).

~~~jsx
<Banner kind="error">Your config was not loaded, so AeroSpork is running built-in defaults. Fix the error in Raw TOML or your editor; the config reloads by itself.</Banner>
~~~

Copy names the state, then what to do, then reassures that recovery is automatic. Text is selectable in the real app.

In the app a banner can carry one button that performs the recovery, labelled with what it does: "Show in Raw TOML", or "Discard edits and load from disk" when the file changed under unsaved edits. The kit component shows the text only.
