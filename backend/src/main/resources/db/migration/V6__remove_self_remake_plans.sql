DELETE rp
FROM remake_plans rp
JOIN posts p ON p.id = rp.original_post_id
WHERE rp.user_id = p.author_id;
