with latest_version column and index on document_type, latest_version
```sql
explain analyze
select content_items.content_id, content_items.id, content_items.user_facing_version, content_items.locale from content_items
where latest_version = true and document_type = 'aaib_report';
```
Execution time: 25.681 ms

latest with window function
```sql
explain analyze
select content_items.content_id, content_items.id, content_items.user_facing_version, content_items.locale from content_items
join( select id, content_id, max(user_facing_version) over(partition by content_id, locale) as latest_version, locale, user_facing_version from content_items
where content_items.document_type = 'aaib_report') as latest
on latest.id = content_items.id and latest.latest_version = content_items.user_facing_version
where content_items.document_type = 'aaib_report';
```
Execution time: 526.917 ms


latest with group by
```sql
explain analyze
select content_items.content_id, id, user_facing_version, content_items.locale from content_items
join( select content_id, max(user_facing_version) as latest_version, locale from content_items
where content_items.document_type = 'aaib_report'
group by content_id, locale) latest on
latest.content_id = content_items.content_id and latest.latest_version = content_items.user_facing_version and content_items.locale = latest.locale
where content_items.document_type = 'aaib_report';
```
Execution time: 1000.170 ms
