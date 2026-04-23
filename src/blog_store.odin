package main

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:sort"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"


BLOG_DATA_ROOT :: "data/blog"
BLOG_MEDIA_URL_PREFIX :: "/media/blog"
BLOG_ASSETS_DIR_NAME :: "assets"

Blog_Post_Metadata :: struct {
	id:          string,
	slug:        string,
	title:       string,
	status:      string,
	publishedAt: string,
	updatedAt:   string,
	createdAt:   string,
	author:      string,
}

Blog_Post_Document :: struct {
	meta:     Blog_Post_Metadata,
	markdown: string,
}

Blog_Post_Save_Input :: struct {
	title:       string,
	slug:        string,
	status:      string,
	publishedAt: string,
	markdown:    string,
}

blog_post_exists :: proc(slug: string) -> bool {
	return os.exists(blog_post_meta_path(slug))
}

blog_slugify :: proc(s: string, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	defer strings.builder_destroy(&sb)

	prev_dash := false
	for r in s {
		b := byte(r)
		is_alpha := (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z')
		is_num := b >= '0' && b <= '9'
		if is_alpha {
			if b >= 'A' && b <= 'Z' {
				b += 'a' - 'A'
			}
			strings.write_byte(&sb, b)
			prev_dash = false
			continue
		}
		if is_num {
			strings.write_byte(&sb, b)
			prev_dash = false
			continue
		}
		if !prev_dash && strings.builder_len(sb) > 0 {
			strings.write_byte(&sb, '-')
			prev_dash = true
		}
	}

	res := strings.trim(strings.to_string(sb), "-")
	if res == "" {
		return fmt.tprintf("post-%s", generate_random_string(8, "abcdefghijklmnopqrstuvwxyz0123456789", allocator))
	}
	return res
}

blog_status_normalize :: proc(status: string) -> string {
	if status == "published" {
		return "published"
	}
	return "draft"
}

blog_post_dir :: proc(slug: string, allocator := context.temp_allocator) -> string {
	path, _ := os.join_path({BLOG_DATA_ROOT, slug}, allocator)
	return path
}

blog_post_meta_path :: proc(slug: string, allocator := context.temp_allocator) -> string {
	path, _ := os.join_path({BLOG_DATA_ROOT, slug, "post.json"}, allocator)
	return path
}

blog_post_content_path :: proc(slug: string, allocator := context.temp_allocator) -> string {
	path, _ := os.join_path({BLOG_DATA_ROOT, slug, "content.md"}, allocator)
	return path
}

blog_post_assets_dir :: proc(slug: string, allocator := context.temp_allocator) -> string {
	path, _ := os.join_path({BLOG_DATA_ROOT, slug, BLOG_ASSETS_DIR_NAME}, allocator)
	return path
}

ensure_blog_root_exists :: proc() -> Error {
	if os.exists(BLOG_DATA_ROOT) {
		return Error{type = .None}
	}
	if err := os.make_directory_all(BLOG_DATA_ROOT); err != nil {
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not create %s: %v", BLOG_DATA_ROOT, err)}
	}
	return Error{type = .None}
}

current_timestamp_rfc3339 :: proc(allocator := context.temp_allocator) -> string {
	res, _ := time.time_to_rfc3339(time.now(), 0, false, allocator)
	return res
}

compute_blog_excerpt :: proc(markdown: string, allocator := context.temp_allocator) -> string {
	return markdown_to_excerpt(markdown, 180, allocator)
}

published_at_to_datetime_local :: proc(published_at: string, allocator := context.temp_allocator) -> string {
	if strings.trim_space(published_at) == "" {
		return ""
	}

	tm, _, consumed := time.iso8601_to_time_and_offset(published_at)
	if consumed == 0 {
		return ""
	}
	dt, ok := time.time_to_datetime(tm)
	if !ok {
		return ""
	}
	local_dt := timezone.datetime_to_tz(dt, TIMEZONE)
	return fmt.tprintf(
		"%04d-%02d-%02dT%02d:%02d",
		local_dt.year,
		local_dt.month,
		local_dt.day,
		local_dt.hour,
		local_dt.minute,
	)
}

blog_post_sort_key :: proc(meta: Blog_Post_Metadata) -> string {
	if meta.publishedAt != "" {
		return meta.publishedAt
	}
	if meta.updatedAt != "" {
		return meta.updatedAt
	}
	return meta.createdAt
}

load_blog_post_metadata_by_slug :: proc(slug: string) -> (Blog_Post_Metadata, Error) {
	meta_path := blog_post_meta_path(slug)
	json_bytes, err := os.read_entire_file_from_path(meta_path, context.temp_allocator)
	if err != nil {
		return Blog_Post_Metadata{}, Error{
			type = .Filesystem,
			msg  = fmt.tprintf("Could not read blog metadata for %s: %v", slug, err),
		}
	}

	meta: Blog_Post_Metadata
	if uerr := json.unmarshal(json_bytes, &meta, allocator = context.temp_allocator); uerr != nil {
		return Blog_Post_Metadata{}, Error{
			type = .JSON_Unmarshal,
			msg  = fmt.tprintf("Could not decode blog metadata for %s: %v", slug, uerr),
		}
	}

	if meta.author == "" {
		meta.author = ME.fullName
	}
	meta.status = blog_status_normalize(meta.status)
	return meta, Error{type = .None}
}

load_blog_post_document :: proc(slug: string, include_drafts := false) -> (Blog_Post_Document, Error) {
	meta, err := load_blog_post_metadata_by_slug(slug)
	if err.type != .None {
		return Blog_Post_Document{}, err
	}
	if !include_drafts && meta.status != "published" {
		return Blog_Post_Document{}, Error{type = .Validation, msg = "Post is not published"}
	}

	content_path := blog_post_content_path(slug)
	content_bytes, read_err := os.read_entire_file_from_path(content_path, context.temp_allocator)
	if read_err != nil {
		return Blog_Post_Document{}, Error{
			type = .Filesystem,
			msg  = fmt.tprintf("Could not read blog markdown for %s: %v", slug, read_err),
		}
	}

	return Blog_Post_Document{
		meta     = meta,
		markdown = string(content_bytes),
	}, Error{type = .None}
}

list_blog_post_metadata :: proc(include_drafts := false) -> ([]Blog_Post_Metadata, Error) {
	if !os.exists(BLOG_DATA_ROOT) {
		return []Blog_Post_Metadata{}, Error{type = .None}
	}

	entries, err := os.read_all_directory_by_path(BLOG_DATA_ROOT, context.temp_allocator)
	if err != nil {
		return nil, Error{type = .Filesystem, msg = fmt.tprintf("Could not list %s: %v", BLOG_DATA_ROOT, err)}
	}

	metas := make([dynamic]Blog_Post_Metadata, context.temp_allocator)
	for entry in entries {
		if entry.type != .Directory {
			continue
		}
		meta, meta_err := load_blog_post_metadata_by_slug(entry.name)
		if meta_err.type != .None {
			log.warnf("Skipping blog directory %s: %s", entry.name, meta_err.msg)
			continue
		}
		if !include_drafts && meta.status != "published" {
			continue
		}
		append(&metas, meta)
	}

	sort.quick_sort_proc(
		metas[:],
		proc(a, b: Blog_Post_Metadata) -> int {
			ta, _, _ := time.iso8601_to_time_and_offset(blog_post_sort_key(a))
			tb, _, _ := time.iso8601_to_time_and_offset(blog_post_sort_key(b))
			return int(clamp(time.time_to_unix_nano(tb) - time.time_to_unix_nano(ta), -1, 1))
		},
	)

	return metas[:], Error{type = .None}
}

fetch_local_posts :: proc() -> (posts: []Post, err: Error) {
	metas, list_err := list_blog_post_metadata(false)
	if list_err.type != .None {
		return nil, list_err
	}

	posts_dyn := make([dynamic]Post, context.temp_allocator)
	for meta in metas {
		excerpt := ""
		content_bytes, read_err := os.read_entire_file_from_path(blog_post_content_path(meta.slug), context.temp_allocator)
		if read_err == nil {
			excerpt = compute_blog_excerpt(string(content_bytes), context.temp_allocator)
		} else {
			log.warnf("Could not read blog markdown for excerpt %s: %v", meta.slug, read_err)
		}

		append(
			&posts_dyn,
			Post{
				slug        = meta.slug,
				title       = meta.title,
				excerpt     = excerpt,
				publishedAt = blog_post_sort_key(meta),
				updatedAt   = meta.updatedAt,
				createdAt   = meta.createdAt,
				author      = Post_Author{name = meta.author},
			},
		)
	}

	return posts_dyn[:], Error{type = .None}
}

fetch_local_post :: proc(slug: string) -> (post: Post_Detail, err: Error) {
	doc, load_err := load_blog_post_document(slug, false)
	if load_err.type != .None {
		return Post_Detail{}, load_err
	}

	html := markdown_to_html(doc.markdown, context.temp_allocator)
	text := markdown_to_plain_text(doc.markdown, context.temp_allocator)

	return Post_Detail{
		slug      = doc.meta.slug,
		title     = doc.meta.title,
		updatedAt = doc.meta.updatedAt,
		createdAt = doc.meta.createdAt,
		author    = Post_Author{name = doc.meta.author},
		content   = {
			html = html,
			text = text,
		},
	}, Error{type = .None}
}

build_blog_editor_form :: proc(doc: Blog_Post_Document, current_slug: string, is_new: bool, allocator := context.temp_allocator) -> Blog_Post_Form_Data {
	form_action := "/admin/blogposts/new"
	if !is_new {
		form_action = fmt.tprintf("/admin/blogposts/%s/save", current_slug)
	}

	public_url := ""
	if current_slug != "" {
		public_url = fmt.tprintf("/blog/%s", current_slug)
	}

	return Blog_Post_Form_Data{
		Title       = doc.meta.title,
		Slug        = doc.meta.slug,
		Status      = doc.meta.status,
		PublishedAt = published_at_to_datetime_local(doc.meta.publishedAt, allocator),
		Markdown    = doc.markdown,
		CreatedAt   = doc.meta.createdAt,
		UpdatedAt   = doc.meta.updatedAt,
		IsNew       = is_new,
		FormAction  = form_action,
		PublicUrl   = public_url,
	}
}

empty_blog_post_document :: proc(allocator := context.temp_allocator) -> Blog_Post_Document {
	now := current_timestamp_rfc3339(allocator)
	return Blog_Post_Document{
		meta = Blog_Post_Metadata{
			id          = "",
			slug        = "",
			title       = "",
			status      = "draft",
			publishedAt = "",
			updatedAt   = now,
			createdAt   = now,
			author      = ME.fullName,
		},
		markdown = "",
	}
}

save_blog_post :: proc(input: Blog_Post_Save_Input, old_slug := "") -> (saved_slug: string, err: Error) {
	ensure_err := ensure_blog_root_exists()
	if ensure_err.type != .None {
		return "", ensure_err
	}

	title := strings.trim_space(input.title)
	if title == "" {
		return "", Error{type = .Validation, msg = "Title is required"}
	}

	new_slug := blog_slugify(strings.trim_space(input.slug))
	if new_slug == "" {
		return "", Error{type = .Validation, msg = "Slug is required"}
	}

	status := blog_status_normalize(strings.trim_space(input.status))
	now := current_timestamp_rfc3339()

	existing := empty_blog_post_document()
	if old_slug != "" && blog_post_exists(old_slug) {
		existing, err = load_blog_post_document(old_slug, true)
		if err.type != .None {
			return "", err
		}
	}

	current_slug := strings.trim_space(old_slug)
	old_dir := blog_post_dir(current_slug)
	new_dir := blog_post_dir(new_slug)

	if current_slug == "" && blog_post_exists(new_slug) {
		return "", Error{type = .Validation, msg = fmt.tprintf("A blogpost with slug '%s' already exists", new_slug)}
	}
	if current_slug != "" && current_slug != new_slug && blog_post_exists(new_slug) {
		return "", Error{type = .Validation, msg = fmt.tprintf("A blogpost with slug '%s' already exists", new_slug)}
	}

	markdown := normalize_markdown_newlines(input.markdown)
	if current_slug != "" && current_slug != new_slug {
		markdown, _ = strings.replace_all(
			markdown,
			fmt.tprintf("%s/%s/", BLOG_MEDIA_URL_PREFIX, current_slug),
			fmt.tprintf("%s/%s/", BLOG_MEDIA_URL_PREFIX, new_slug),
			context.temp_allocator,
		)
	}

	if current_slug != "" && current_slug != new_slug && os.exists(old_dir) {
		if rename_err := os.rename(old_dir, new_dir); rename_err != nil {
			return "", Error{
				type = .Filesystem,
				msg  = fmt.tprintf("Could not rename blogpost directory to %s: %v", new_slug, rename_err),
			}
		}
	}

	if !os.exists(new_dir) {
		if mkdir_err := os.make_directory_all(new_dir); mkdir_err != nil {
			return "", Error{type = .Filesystem, msg = fmt.tprintf("Could not create blog directory %s: %v", new_slug, mkdir_err)}
		}
	}

	created_at := existing.meta.createdAt
	if created_at == "" {
		created_at = now
	}
	updated_at := now
	published_at := datetime_local_to_utc_rfc3339(input.publishedAt, TIMEZONE, context.temp_allocator)
	if strings.trim_space(input.publishedAt) != "" && published_at == "" {
		return "", Error{type = .Validation, msg = "Published at must be a valid datetime"}
	}
	if status == "published" && published_at == "" {
		if existing.meta.publishedAt != "" {
			published_at = existing.meta.publishedAt
		} else {
			published_at = created_at
		}
	}

	meta := Blog_Post_Metadata{
		id          = existing.meta.id,
		slug        = new_slug,
		title       = title,
		status      = status,
		publishedAt = published_at,
		updatedAt   = updated_at,
		createdAt   = created_at,
		author      = ME.fullName,
	}
	if meta.id == "" {
		meta.id = new_slug
	}

	meta_json, marshal_err := json.marshal(meta, {pretty = true}, context.temp_allocator)
	if marshal_err != nil {
		return "", Error{type = .JSON_Marshal, msg = fmt.tprintf("Could not encode blog metadata: %v", marshal_err)}
	}

	if write_err := os.write_entire_file_from_bytes(blog_post_meta_path(new_slug), meta_json); write_err != nil {
		return "", Error{type = .Filesystem, msg = fmt.tprintf("Could not write blog metadata: %v", write_err)}
	}
	if write_err := os.write_entire_file_from_bytes(
		blog_post_content_path(new_slug),
		transmute([]u8)markdown,
	); write_err != nil {
		return "", Error{type = .Filesystem, msg = fmt.tprintf("Could not write blog markdown: %v", write_err)}
	}

	return new_slug, Error{type = .None}
}

blog_uploaded_file_stem :: proc(name: string, allocator := context.temp_allocator) -> string {
	stem := os.short_stem(name)
	stem = blog_slugify(stem, allocator)
	if stem == "" {
		return "image"
	}
	return stem
}

blog_mime_extension :: proc(mime_type: string) -> string {
	switch mime_type {
	case "image/png":
		return ".png"
	case "image/jpeg":
		return ".jpg"
	case "image/webp":
		return ".webp"
	case "image/gif":
		return ".gif"
	case "image/svg+xml":
		return ".svg"
	case:
		return ""
	}
}

blog_uploaded_asset_url :: proc(slug, filename: string, allocator := context.temp_allocator) -> string {
	return fmt.tprintf("%s/%s/assets/%s", BLOG_MEDIA_URL_PREFIX, slug, filename)
}

Blog_Post_Form_Data :: struct {
	Title:       string,
	Slug:        string,
	Status:      string,
	PublishedAt: string,
	Markdown:    string,
	CreatedAt:   string,
	UpdatedAt:   string,
	IsNew:       bool,
	FormAction:  string,
	PublicUrl:   string,
}

Admin_Blog_List_Item :: struct {
	Title:       string,
	Slug:        string,
	Status:      string,
	UpdatedAt:   string,
	PublishedAt: string,
}
