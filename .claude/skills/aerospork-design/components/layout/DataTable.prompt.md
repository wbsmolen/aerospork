Use for editable lists with more than one field per row (workspace assignments, window rules). Always pair with ListActionBar and an emptyState.

~~~jsx
<DataTable selected={sel} onSelect={setSel} rows={rules}
  columns={[{ key: 'match', title: 'Matches', width: '1fr' }, { key: 'run', title: 'Run' }]}
  emptyState={<ContentUnavailable sf="macwindow" title="No window rules" message="Rules run once, when a window first appears." actionTitle="Add rule" onAction={add} />} />
~~~
