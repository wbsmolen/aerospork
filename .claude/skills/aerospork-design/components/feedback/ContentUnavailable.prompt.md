Use for every empty list, empty filter result and unselected detail pane — a section header floating above nothing is the thing this replaces.

~~~jsx
<ContentUnavailable sf="arrow.triangle.branch" title="No assignments"
  message="Workspaces land wherever they were last used. Add an assignment to pin one to a specific monitor."
  actionTitle="Add assignment" onAction={add} />
~~~

The message teaches the feature; only offer an action when this pane can create the first item.
