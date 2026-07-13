package main

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:sort"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"


BLOG_MEDIA_URL_PREFIX :: "/media/blog"
BLOG_ASSETS_DIR_NAME :: "assets"

Blog_Store :: struct {
	root:   string,
	mu:     sync.Mutex,
	author: string,
}

Blog_Post_Metadata :: struct {
	id:          string,
	slug:        string,
	title:       string,
	language:    string,
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
	language:    string,
	status:      string,
	publishedAt: string,
	markdown:    string,
}

blog_slug_is_valid :: proc(slug: string) -> bool {
	if slug == "" || slug[0] == '-' || slug[len(slug) - 1] == '-' {
		return false
	}
	previous_dash := false
	for c in slug {
		is_letter := c >= 'a' && c <= 'z'
		is_number := c >= '0' && c <= '9'
		if !is_letter && !is_number && c != '-' {
			return false
		}
		if c == '-' {
			if previous_dash {
				return false
			}
			previous_dash = true
		} else {
			previous_dash = false
		}
	}
	return true
}

blog_asset_filename_is_valid :: proc(filename: string) -> bool {
	if filename == "" || filename == "." || filename == ".." || filename[0] == '.' {
		return false
	}
	for c in filename {
		is_letter := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
		is_number := c >= '0' && c <= '9'
		if !is_letter && !is_number && c != '-' && c != '_' && c != '.' {
			return false
		}
	}
	ext := strings.to_lower(os.ext(filename), context.temp_allocator)
	switch ext {
	case ".png", ".jpg", ".jpeg", ".webp", ".gif":
		return true
	case:
		return false
	}
}

blog_require_path_type :: proc(path, description: string, expected: os.File_Type) -> Error {
	info, stat_err := os.lstat(path, context.temp_allocator)
	if stat_err != nil {
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not inspect %s: %v", description, stat_err)}
	}
	if info.type != expected {
		return Error{type = .Validation, msg = fmt.tprintf("Invalid %s", description)}
	}
	return Error{type = .None}
}

blog_validate_directory_chain :: proc(path: string) -> Error {
	if path == "" || path == "." {
		return Error{type = .None}
	}
	parent := os.dir(path)
	if parent != path {
		if parent_err := blog_validate_directory_chain(parent); parent_err.type != .None {
			return parent_err
		}
	}
	return blog_require_path_type(path, "blog storage path", .Directory)
}

blog_ensure_directory_chain :: proc(path: string) -> Error {
	if path == "" || path == "." {
		return Error{type = .None}
	}
	parent := os.dir(path)
	if parent != path {
		if parent_err := blog_ensure_directory_chain(parent); parent_err.type != .None {
			return parent_err
		}
	}
	if os.exists(path) {
		return blog_require_path_type(path, "blog storage path", .Directory)
	}
	if mkdir_err := os.make_directory(path); mkdir_err != nil {
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not create blog storage path: %v", mkdir_err)}
	}
	return blog_require_path_type(path, "blog storage path", .Directory)
}

blog_directory_entry :: proc(dir, name: string) -> (entry_type: os.File_Type, found: bool, err: Error) {
	entries, read_err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if read_err != nil {
		return .Undetermined, false, Error{
			type = .Filesystem,
			msg  = fmt.tprintf("Could not inspect blog storage: %v", read_err),
		}
	}
	for entry in entries {
		if entry.name == name {
			return entry.type, true, Error{type = .None}
		}
	}
	return .Undetermined, false, Error{type = .None}
}

blog_validate_assets_directory_unlocked :: proc(store: ^Blog_Store, slug: string) -> Error {
	assets_dir := blog_post_assets_dir(store, slug)
	entries, read_err := os.read_all_directory_by_path(assets_dir, context.temp_allocator)
	if read_err != nil {
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not inspect blog assets: %v", read_err)}
	}
	for entry in entries {
		if entry.type != .Regular || !blog_asset_filename_is_valid(entry.name) {
			return Error{type = .Validation, msg = "Blog assets must be regular image files"}
		}
	}
	return Error{type = .None}
}

blog_validate_post_directory_unlocked :: proc(store: ^Blog_Store, slug: string, require_document := true) -> Error {
	if !blog_slug_is_valid(slug) {
		return Error{type = .Validation, msg = "Invalid blogpost slug"}
	}
	post_dir := blog_post_dir(store, slug)
	if type_err := blog_require_path_type(post_dir, "blogpost directory", .Directory); type_err.type != .None {
		return type_err
	}

	entries, read_err := os.read_all_directory_by_path(post_dir, context.temp_allocator)
	if read_err != nil {
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not inspect blogpost directory: %v", read_err)}
	}
	meta_found, content_found := false, false
	for entry in entries {
		switch entry.name {
		case "post.json":
			if entry.type != .Regular {
				return Error{type = .Validation, msg = "Blog metadata must be a regular file"}
			}
			meta_found = true
		case "content.md":
			if entry.type != .Regular {
				return Error{type = .Validation, msg = "Blog content must be a regular file"}
			}
			content_found = true
		case BLOG_ASSETS_DIR_NAME:
			if entry.type != .Directory {
				return Error{type = .Validation, msg = "Blog assets must be a directory"}
			}
			if assets_err := blog_validate_assets_directory_unlocked(store, slug); assets_err.type != .None {
				return assets_err
			}
		case:
			return Error{type = .Validation, msg = "Blogpost directory contains unsupported files"}
		}
	}
	if require_document && (!meta_found || !content_found) {
		return Error{type = .Validation, msg = "Blogpost is incomplete"}
	}
	if !require_document && meta_found != content_found {
		return Error{type = .Validation, msg = "Blogpost is incomplete"}
	}
	return Error{type = .None}
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

blog_post_dir :: proc(store: ^Blog_Store, slug: string, allocator := context.temp_allocator) -> string {
	path, _ := os.join_path({store.root, slug}, allocator)
	return path
}

blog_post_meta_path :: proc(store: ^Blog_Store, slug: string, allocator := context.temp_allocator) -> string {
	path, _ := os.join_path({store.root, slug, "post.json"}, allocator)
	return path
}

blog_post_content_path :: proc(store: ^Blog_Store, slug: string, allocator := context.temp_allocator) -> string {
	path, _ := os.join_path({store.root, slug, "content.md"}, allocator)
	return path
}

blog_post_assets_dir :: proc(store: ^Blog_Store, slug: string, allocator := context.temp_allocator) -> string {
	path, _ := os.join_path({store.root, slug, BLOG_ASSETS_DIR_NAME}, allocator)
	return path
}

blog_validate_store_root_value :: proc(store: ^Blog_Store) -> Error {
	if store.root == "" || store.root == "." {
		return Error{type = .Validation, msg = "Blog storage root is invalid"}
	}
	clean_root, clean_err := os.clean_path(store.root, context.temp_allocator)
	if clean_err != nil || clean_root != store.root {
		return Error{type = .Validation, msg = "Blog storage root must be a normalized path"}
	}
	return Error{type = .None}
}

blog_validate_storage_root_unlocked :: proc(store: ^Blog_Store) -> Error {
	if root_err := blog_validate_store_root_value(store); root_err.type != .None {
		return root_err
	}
	return blog_validate_directory_chain(store.root)
}

ensure_blog_root_exists :: proc(store: ^Blog_Store) -> Error {
	if root_err := blog_validate_store_root_value(store); root_err.type != .None {
		return root_err
	}
	return blog_ensure_directory_chain(store.root)
}

current_timestamp_rfc3339 :: proc(allocator := context.temp_allocator) -> string {
	res, _ := time.time_to_rfc3339(time.now(), 0, false, allocator)
	return res
}

compute_blog_excerpt :: proc(markdown: string, allocator := context.temp_allocator) -> string {
	return markdown_to_excerpt(markdown, 180, allocator)
}

published_at_to_datetime_local :: proc(published_at: string, tz: ^datetime.TZ_Region, allocator := context.temp_allocator) -> string {
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
	local_dt := timezone.datetime_to_tz(dt, tz)
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

load_blog_post_metadata_by_slug_unlocked :: proc(store: ^Blog_Store, slug: string) -> (Blog_Post_Metadata, Error) {
	if !blog_slug_is_valid(slug) {
		return Blog_Post_Metadata{}, Error{type = .Validation, msg = "Invalid blogpost slug"}
	}
	if root_err := blog_validate_storage_root_unlocked(store); root_err.type != .None {
		return Blog_Post_Metadata{}, root_err
	}
	if validate_err := blog_validate_post_directory_unlocked(store, slug); validate_err.type != .None {
		return Blog_Post_Metadata{}, validate_err
	}

	meta_path := blog_post_meta_path(store, slug)
	json_bytes, read_err := os.read_entire_file_from_path(meta_path, context.temp_allocator)
	if read_err != nil {
		return Blog_Post_Metadata{}, Error{
			type = .Filesystem,
			msg  = fmt.tprintf("Could not read blog metadata for %s: %v", slug, read_err),
		}
	}

	meta: Blog_Post_Metadata
	if unmarshal_err := json.unmarshal(json_bytes, &meta, allocator = context.temp_allocator); unmarshal_err != nil {
		return Blog_Post_Metadata{}, Error{
			type = .JSON_Unmarshal,
			msg  = fmt.tprintf("Could not decode blog metadata for %s: %v", slug, unmarshal_err),
		}
	}
	if meta.slug != slug || !blog_slug_is_valid(meta.slug) {
		return Blog_Post_Metadata{}, Error{type = .Validation, msg = "Blog metadata slug does not match its directory"}
	}
	if meta.status != "draft" && meta.status != "published" {
		return Blog_Post_Metadata{}, Error{type = .Validation, msg = "Blog metadata has an invalid status"}
	}
	// Language was added after the first on-disk blog format; migrate legacy posts explicitly.
	if meta.language == "" {
		meta.language = "en"
	}
	if meta.language != "en" && meta.language != "fr" {
		return Blog_Post_Metadata{}, Error{type = .Validation, msg = "Blog metadata has an invalid language"}
	}
	if meta.author == "" {
		meta.author = store.author
	}
	return meta, Error{type = .None}
}

load_blog_post_metadata_by_slug :: proc(store: ^Blog_Store, slug: string) -> (Blog_Post_Metadata, Error) {
	sync.lock(&store.mu)
	defer sync.unlock(&store.mu)
	return load_blog_post_metadata_by_slug_unlocked(store, slug)
}

load_blog_post_document_unlocked :: proc(store: ^Blog_Store, slug: string, include_drafts := false) -> (Blog_Post_Document, Error) {
	meta, err := load_blog_post_metadata_by_slug_unlocked(store, slug)
	if err.type != .None {
		return Blog_Post_Document{}, err
	}
	if !include_drafts && meta.status != "published" {
		return Blog_Post_Document{}, Error{type = .Validation, msg = "Post is not published"}
	}

	content_path := blog_post_content_path(store, slug)
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

load_blog_post_document :: proc(store: ^Blog_Store, slug: string, include_drafts := false) -> (Blog_Post_Document, Error) {
	sync.lock(&store.mu)
	defer sync.unlock(&store.mu)
	return load_blog_post_document_unlocked(store, slug, include_drafts)
}

list_blog_post_metadata_unlocked :: proc(store: ^Blog_Store, include_drafts := false) -> ([]Blog_Post_Metadata, Error) {
	if !os.exists(store.root) {
		return []Blog_Post_Metadata{}, Error{type = .None}
	}
	if root_err := blog_validate_storage_root_unlocked(store); root_err.type != .None {
		return nil, root_err
	}

	entries, read_err := os.read_all_directory_by_path(store.root, context.temp_allocator)
	if read_err != nil {
		return nil, Error{type = .Filesystem, msg = fmt.tprintf("Could not list %s: %v", store.root, read_err)}
	}

	metas := make([dynamic]Blog_Post_Metadata, context.temp_allocator)
	for entry in entries {
		if entry.type != .Directory || !blog_slug_is_valid(entry.name) {
			continue
		}
		meta, meta_err := load_blog_post_metadata_by_slug_unlocked(store, entry.name)
		if meta_err.type != .None {
			log.warnf("Skipping invalid blog directory %s: %s", entry.name, meta_err.msg)
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

list_blog_post_metadata :: proc(store: ^Blog_Store, include_drafts := false) -> ([]Blog_Post_Metadata, Error) {
	sync.lock(&store.mu)
	defer sync.unlock(&store.mu)
	return list_blog_post_metadata_unlocked(store, include_drafts)
}

fetch_local_posts :: proc(store: ^Blog_Store) -> (posts: []Post, err: Error) {
	sync.lock(&store.mu)
	defer sync.unlock(&store.mu)

	metas, list_err := list_blog_post_metadata_unlocked(store, false)
	if list_err.type != .None {
		return nil, list_err
	}

	posts_dyn := make([dynamic]Post, context.temp_allocator)
	for meta in metas {
		content_bytes, read_err := os.read_entire_file_from_path(blog_post_content_path(store, meta.slug), context.temp_allocator)
		if read_err != nil {
			log.warnf("Skipping blogpost with unreadable markdown %s: %v", meta.slug, read_err)
			continue
		}

		append(
			&posts_dyn,
			Post{
				slug        = meta.slug,
				title       = meta.title,
				excerpt     = compute_blog_excerpt(string(content_bytes), context.temp_allocator),
				language    = meta.language,
				publishedAt = blog_post_sort_key(meta),
				updatedAt   = meta.updatedAt,
				createdAt   = meta.createdAt,
				author      = Post_Author{name = meta.author},
			},
		)
	}

	return posts_dyn[:], Error{type = .None}
}

fetch_local_post :: proc(store: ^Blog_Store, slug: string) -> (post: Post_Detail, err: Error) {
	doc, load_err := load_blog_post_document(store, slug, false)
	if load_err.type != .None {
		return Post_Detail{}, load_err
	}

	html := markdown_to_html(doc.markdown, context.temp_allocator)
	text := markdown_to_plain_text(doc.markdown, context.temp_allocator)

	return Post_Detail{
		slug      = doc.meta.slug,
		title     = doc.meta.title,
		language  = doc.meta.language,
		updatedAt = doc.meta.updatedAt,
		createdAt = doc.meta.createdAt,
		author    = Post_Author{name = doc.meta.author},
		content   = {
			html = html,
			text = text,
		},
	}, Error{type = .None}
}

build_blog_editor_form :: proc(doc: Blog_Post_Document, current_slug: string, is_new: bool, tz: ^datetime.TZ_Region, allocator := context.temp_allocator) -> Blog_Post_Form_Data {
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
		Language     = doc.meta.language,
		PublishedAt = published_at_to_datetime_local(doc.meta.publishedAt, tz, allocator),
		Markdown    = doc.markdown,
		CreatedAt   = doc.meta.createdAt,
		UpdatedAt   = doc.meta.updatedAt,
		IsNew       = is_new,
		FormAction  = form_action,
		PublicUrl   = public_url,
	}
}

empty_blog_post_document :: proc(store: ^Blog_Store, allocator := context.temp_allocator) -> Blog_Post_Document {
	now := current_timestamp_rfc3339(allocator)
	return Blog_Post_Document{
		meta = Blog_Post_Metadata{
			id          = "",
			slug        = "",
			title       = "",
			language    = "en",
			status      = "draft",
			publishedAt = "",
			updatedAt   = now,
			createdAt   = now,
			author      = store.author,
		},
		markdown = "",
	}
}

blog_asset_bytes_match_extension :: proc(filename: string, data: []u8) -> bool {
	ext := strings.to_lower(os.ext(filename), context.temp_allocator)
	switch ext {
	case ".png":
		return len(data) >= 8 &&
			data[0] == 0x89 && data[1] == 'P' && data[2] == 'N' && data[3] == 'G' &&
			data[4] == 0x0d && data[5] == 0x0a && data[6] == 0x1a && data[7] == 0x0a
	case ".jpg", ".jpeg":
		return len(data) >= 3 && data[0] == 0xff && data[1] == 0xd8 && data[2] == 0xff
	case ".gif":
		return len(data) >= 6 && data[0] == 'G' && data[1] == 'I' && data[2] == 'F' &&
			data[3] == '8' && (data[4] == '7' || data[4] == '9') && data[5] == 'a'
	case ".webp":
		return len(data) >= 12 && data[0] == 'R' && data[1] == 'I' && data[2] == 'F' && data[3] == 'F' &&
			data[8] == 'W' && data[9] == 'E' && data[10] == 'B' && data[11] == 'P'
	case:
		return false
	}
}

blog_write_atomic_file :: proc(path: string, data: []u8) -> Error {
	dir := os.dir(path)
	file, create_err := os.create_temp_file(dir, ".blog-write-*")
	if create_err != nil {
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not create temporary blog file: %v", create_err)}
	}
	file_open := true
	temp_path := fmt.tprintf("%s", os.name(file))
	temp_exists := true
	defer {
		if file_open {
			_ = os.close(file)
		}
		if temp_exists {
			_ = os.remove(temp_path)
		}
	}

	if _, write_err := os.write(file, data); write_err != nil {
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not write temporary blog file: %v", write_err)}
	}
	if sync_err := os.sync(file); sync_err != nil {
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not sync temporary blog file: %v", sync_err)}
	}
	close_err := os.close(file)
	file_open = false
	if close_err != nil {
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not close temporary blog file: %v", close_err)}
	}
	if rename_err := os.rename(temp_path, path); rename_err != nil {
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not commit blog file: %v", rename_err)}
	}
	temp_exists = false
	return Error{type = .None}
}

blog_copy_assets_to_stage_unlocked :: proc(store: ^Blog_Store, source_slug, stage_dir: string) -> Error {
	source_assets := blog_post_assets_dir(store, source_slug)
	_, found, entry_err := blog_directory_entry(blog_post_dir(store, source_slug), BLOG_ASSETS_DIR_NAME)
	if entry_err.type != .None {
		return entry_err
	}
	if !found {
		return Error{type = .None}
	}

	stage_assets, _ := os.join_path({stage_dir, BLOG_ASSETS_DIR_NAME}, context.temp_allocator)
	if !os.exists(stage_assets) {
		if mkdir_err := os.make_directory(stage_assets); mkdir_err != nil {
			return Error{type = .Filesystem, msg = fmt.tprintf("Could not stage blog assets: %v", mkdir_err)}
		}
	}
	entries, read_err := os.read_all_directory_by_path(source_assets, context.temp_allocator)
	if read_err != nil {
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not read blog assets: %v", read_err)}
	}
	for entry in entries {
		source_path, _ := os.join_path({source_assets, entry.name}, context.temp_allocator)
		asset_bytes, asset_err := os.read_entire_file_from_path(source_path, context.temp_allocator)
		if asset_err != nil {
			return Error{type = .Filesystem, msg = fmt.tprintf("Could not read blog asset: %v", asset_err)}
		}
		destination_path, _ := os.join_path({stage_assets, entry.name}, context.temp_allocator)
		if os.exists(destination_path) {
			return Error{type = .Validation, msg = "Blog asset filename collision"}
		}
		if write_err := blog_write_atomic_file(destination_path, asset_bytes); write_err.type != .None {
			return write_err
		}
	}
	return Error{type = .None}
}

blog_validate_asset_contents_unlocked :: proc(store: ^Blog_Store, slug: string) -> Error {
	post_dir := blog_post_dir(store, slug)
	_, found, entry_err := blog_directory_entry(post_dir, BLOG_ASSETS_DIR_NAME)
	if entry_err.type != .None {
		return entry_err
	}
	if !found {
		return Error{type = .None}
	}
	assets_dir := blog_post_assets_dir(store, slug)
	entries, read_err := os.read_all_directory_by_path(assets_dir, context.temp_allocator)
	if read_err != nil {
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not inspect blog assets: %v", read_err)}
	}
	for entry in entries {
		asset_path, _ := os.join_path({assets_dir, entry.name}, context.temp_allocator)
		asset_bytes, asset_err := os.read_entire_file_from_path(asset_path, context.temp_allocator)
		if asset_err != nil {
			return Error{type = .Filesystem, msg = fmt.tprintf("Could not read blog asset: %v", asset_err)}
		}
		if !blog_asset_bytes_match_extension(entry.name, asset_bytes) {
			return Error{type = .Validation, msg = "Blog asset content does not match its image type"}
		}
	}
	return Error{type = .None}
}

blog_reserve_backup_path_unlocked :: proc(store: ^Blog_Store) -> (string, Error) {
	backup_path, temp_err := os.make_directory_temp(store.root, ".blog-backup-*", context.temp_allocator)
	if temp_err != nil {
		return "", Error{type = .Filesystem, msg = fmt.tprintf("Could not reserve blog backup path: %v", temp_err)}
	}
	if remove_err := os.remove(backup_path); remove_err != nil {
		_ = os.remove_all(backup_path)
		return "", Error{type = .Filesystem, msg = fmt.tprintf("Could not prepare blog backup path: %v", remove_err)}
	}
	return backup_path, Error{type = .None}
}

blog_commit_staged_post_unlocked :: proc(store: ^Blog_Store, stage_dir, primary_source, secondary_source, final_dir: string) -> Error {
	primary_backup, secondary_backup := "", ""
	primary_moved, secondary_moved := false, false

	if primary_source != "" {
		reserve_err: Error
		primary_backup, reserve_err = blog_reserve_backup_path_unlocked(store)
		if reserve_err.type != .None {
			return reserve_err
		}
		if rename_err := os.rename(primary_source, primary_backup); rename_err != nil {
			return Error{type = .Filesystem, msg = fmt.tprintf("Could not prepare blogpost commit: %v", rename_err)}
		}
		primary_moved = true
	}

	if secondary_source != "" {
		reserve_err: Error
		secondary_backup, reserve_err = blog_reserve_backup_path_unlocked(store)
		if reserve_err.type != .None {
			if primary_moved && os.rename(primary_backup, primary_source) != nil {
				return Error{type = .Filesystem, msg = "Could not prepare or restore the previous blogpost"}
			}
			return reserve_err
		}
		if rename_err := os.rename(secondary_source, secondary_backup); rename_err != nil {
			if primary_moved && os.rename(primary_backup, primary_source) != nil {
				return Error{type = .Filesystem, msg = "Could not prepare or restore the previous blogpost"}
			}
			return Error{type = .Filesystem, msg = fmt.tprintf("Could not prepare blogpost commit: %v", rename_err)}
		}
		secondary_moved = true
	}

	if rename_err := os.rename(stage_dir, final_dir); rename_err != nil {
		rollback_failed := false
		if secondary_moved && os.rename(secondary_backup, secondary_source) != nil {
			rollback_failed = true
		}
		if primary_moved && os.rename(primary_backup, primary_source) != nil {
			rollback_failed = true
		}
		if rollback_failed {
			return Error{type = .Filesystem, msg = "Could not commit or restore the previous blogpost"}
		}
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not commit blogpost: %v", rename_err)}
	}

	if primary_moved {
		if cleanup_err := os.remove_all(primary_backup); cleanup_err != nil {
			log.warnf("Could not remove committed blog backup: %v", cleanup_err)
		}
	}
	if secondary_moved {
		if cleanup_err := os.remove_all(secondary_backup); cleanup_err != nil {
			log.warnf("Could not remove committed blog backup: %v", cleanup_err)
		}
	}
	return Error{type = .None}
}

save_blog_post :: proc(store: ^Blog_Store, input: Blog_Post_Save_Input, tz: ^datetime.TZ_Region, old_slug := "") -> (saved_slug: string, err: Error) {
	title := strings.trim_space(input.title)
	if title == "" {
		return "", Error{type = .Validation, msg = "Title is required"}
	}
	raw_slug := strings.trim_space(input.slug)
	if raw_slug == "" {
		return "", Error{type = .Validation, msg = "Slug is required"}
	}
	new_slug := blog_slugify(raw_slug)
	if !blog_slug_is_valid(new_slug) {
		return "", Error{type = .Validation, msg = "Slug is invalid"}
	}
	current_slug := strings.trim_space(old_slug)
	if current_slug != "" && !blog_slug_is_valid(current_slug) {
		return "", Error{type = .Validation, msg = "Current slug is invalid"}
	}
	status := strings.trim_space(input.status)
	if status != "draft" && status != "published" {
		return "", Error{type = .Validation, msg = "Status must be draft or published"}
	}
	language := strings.trim_space(input.language)
	if language != "en" && language != "fr" {
		return "", Error{type = .Validation, msg = "Language must be en or fr"}
	}
	published_at := datetime_local_to_utc_rfc3339(input.publishedAt, tz, context.temp_allocator)
	if strings.trim_space(input.publishedAt) != "" && published_at == "" {
		return "", Error{type = .Validation, msg = "Published at must be a valid datetime"}
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

	sync.lock(&store.mu)
	defer sync.unlock(&store.mu)

	if current_slug != "" && !os.exists(store.root) {
		return "", Error{type = .Validation, msg = "Blogpost to update does not exist"}
	}
	if ensure_err := ensure_blog_root_exists(store); ensure_err.type != .None {
		return "", ensure_err
	}

	existing := empty_blog_post_document(store)
	primary_source, secondary_source := "", ""
	if current_slug != "" {
		entry_type, found, entry_err := blog_directory_entry(store.root, current_slug)
		if entry_err.type != .None {
			return "", entry_err
		}
		if !found || entry_type != .Directory {
			return "", Error{type = .Validation, msg = "Blogpost to update does not exist"}
		}
		existing, err = load_blog_post_document_unlocked(store, current_slug, true)
		if err.type != .None {
			return "", err
		}
		primary_source = blog_post_dir(store, current_slug)
	}

	new_type, new_found, new_entry_err := blog_directory_entry(store.root, new_slug)
	if new_entry_err.type != .None {
		return "", new_entry_err
	}
	if new_found && new_type != .Directory {
		return "", Error{type = .Validation, msg = "Blogpost path is not a directory"}
	}
	if new_found && new_slug != current_slug {
		if validate_err := blog_validate_post_directory_unlocked(store, new_slug, false); validate_err.type != .None {
			return "", validate_err
		}
		meta_type, meta_found, meta_err := blog_directory_entry(blog_post_dir(store, new_slug), "post.json")
		if meta_err.type != .None {
			return "", meta_err
		}
		if meta_found || meta_type != .Undetermined {
			return "", Error{type = .Validation, msg = fmt.tprintf("A blogpost with slug '%s' already exists", new_slug)}
		}
		if primary_source == "" {
			primary_source = blog_post_dir(store, new_slug)
		} else {
			secondary_source = blog_post_dir(store, new_slug)
		}
	}

	now := current_timestamp_rfc3339()
	created_at := existing.meta.createdAt
	if created_at == "" {
		created_at = now
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
		language    = language,
		status      = status,
		publishedAt = published_at,
		updatedAt   = now,
		createdAt   = created_at,
		author      = store.author,
	}
	if meta.id == "" {
		meta.id = new_slug
	}
	meta_json, marshal_err := json.marshal(meta, {pretty = true}, context.temp_allocator)
	if marshal_err != nil {
		return "", Error{type = .JSON_Marshal, msg = fmt.tprintf("Could not encode blog metadata: %v", marshal_err)}
	}

	if primary_source != "" {
		if asset_err := blog_validate_asset_contents_unlocked(store, os.base(primary_source)); asset_err.type != .None {
			return "", asset_err
		}
	}
	if secondary_source != "" {
		if asset_err := blog_validate_asset_contents_unlocked(store, os.base(secondary_source)); asset_err.type != .None {
			return "", asset_err
		}
	}

	stage_dir, stage_err := os.make_directory_temp(store.root, ".blog-stage-*", context.temp_allocator)
	if stage_err != nil {
		return "", Error{type = .Filesystem, msg = fmt.tprintf("Could not create blog staging directory: %v", stage_err)}
	}
	stage_exists := true
	defer if stage_exists {
		_ = os.remove_all(stage_dir)
	}

	if primary_source != "" {
		primary_slug := os.base(primary_source)
		if copy_err := blog_copy_assets_to_stage_unlocked(store, primary_slug, stage_dir); copy_err.type != .None {
			return "", copy_err
		}
	}
	if secondary_source != "" {
		secondary_slug := os.base(secondary_source)
		if copy_err := blog_copy_assets_to_stage_unlocked(store, secondary_slug, stage_dir); copy_err.type != .None {
			return "", copy_err
		}
	}
	stage_meta, _ := os.join_path({stage_dir, "post.json"}, context.temp_allocator)
	if write_err := blog_write_atomic_file(stage_meta, meta_json); write_err.type != .None {
		return "", write_err
	}
	stage_content, _ := os.join_path({stage_dir, "content.md"}, context.temp_allocator)
	if write_err := blog_write_atomic_file(stage_content, transmute([]u8)markdown); write_err.type != .None {
		return "", write_err
	}

	final_dir := blog_post_dir(store, new_slug)
	if commit_err := blog_commit_staged_post_unlocked(store, stage_dir, primary_source, secondary_source, final_dir); commit_err.type != .None {
		return "", commit_err
	}
	stage_exists = false
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
	case:
		return ""
	}
}

blog_upload_extension_matches :: proc(filename, mime_type: string) -> bool {
	trimmed_filename := strings.trim_space(filename)
	if trimmed_filename == "" || trimmed_filename == "." || trimmed_filename == ".." {
		return false
	}
	for c in trimmed_filename {
		if c == '/' || c == '\\' {
			return false
		}
	}
	ext := strings.to_lower(os.ext(trimmed_filename), context.temp_allocator)
	if ext == "" {
		return true
	}
	if mime_type == "image/jpeg" {
		return ext == ".jpg" || ext == ".jpeg"
	}
	return ext == blog_mime_extension(mime_type)
}

save_blog_asset :: proc(store: ^Blog_Store, slug, filename: string, data: []u8) -> Error {
	if !blog_slug_is_valid(slug) {
		return Error{type = .Validation, msg = "Invalid blogpost slug"}
	}
	if !blog_asset_filename_is_valid(filename) || !blog_asset_bytes_match_extension(filename, data) {
		return Error{type = .Validation, msg = "Invalid blog image"}
	}

	sync.lock(&store.mu)
	defer sync.unlock(&store.mu)
	if ensure_err := ensure_blog_root_exists(store); ensure_err.type != .None {
		return ensure_err
	}

	entry_type, post_found, entry_err := blog_directory_entry(store.root, slug)
	if entry_err.type != .None {
		return entry_err
	}
	post_dir := blog_post_dir(store, slug)
	if !post_found {
		stage_dir, stage_err := os.make_directory_temp(store.root, ".blog-assets-stage-*", context.temp_allocator)
		if stage_err != nil {
			return Error{type = .Filesystem, msg = fmt.tprintf("Could not stage blog image: %v", stage_err)}
		}
		stage_exists := true
		defer if stage_exists {
			_ = os.remove_all(stage_dir)
		}
		stage_assets, _ := os.join_path({stage_dir, BLOG_ASSETS_DIR_NAME}, context.temp_allocator)
		if mkdir_err := os.make_directory(stage_assets); mkdir_err != nil {
			return Error{type = .Filesystem, msg = fmt.tprintf("Could not stage blog image directory: %v", mkdir_err)}
		}
		stage_file, _ := os.join_path({stage_assets, filename}, context.temp_allocator)
		if write_err := blog_write_atomic_file(stage_file, data); write_err.type != .None {
			return write_err
		}
		if commit_err := blog_commit_staged_post_unlocked(store, stage_dir, "", "", post_dir); commit_err.type != .None {
			return commit_err
		}
		stage_exists = false
		return Error{type = .None}
	}
	if entry_type != .Directory {
		return Error{type = .Validation, msg = "Blogpost path is not a directory"}
	}
	if validate_err := blog_validate_post_directory_unlocked(store, slug, false); validate_err.type != .None {
		return validate_err
	}
	if validate_err := blog_validate_asset_contents_unlocked(store, slug); validate_err.type != .None {
		return validate_err
	}

	assets_type, assets_found, assets_err := blog_directory_entry(post_dir, BLOG_ASSETS_DIR_NAME)
	if assets_err.type != .None {
		return assets_err
	}
	if assets_found {
		if assets_type != .Directory {
			return Error{type = .Validation, msg = "Blog assets path is not a directory"}
		}
		_, filename_found, filename_err := blog_directory_entry(blog_post_assets_dir(store, slug), filename)
		if filename_err.type != .None {
			return filename_err
		}
		if filename_found {
			return Error{type = .Validation, msg = "Blog image filename already exists"}
		}
		asset_path, _ := os.join_path({blog_post_assets_dir(store, slug), filename}, context.temp_allocator)
		return blog_write_atomic_file(asset_path, data)
	}

	stage_assets, stage_err := os.make_directory_temp(post_dir, ".assets-stage-*", context.temp_allocator)
	if stage_err != nil {
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not stage blog assets: %v", stage_err)}
	}
	stage_exists := true
	defer if stage_exists {
		_ = os.remove_all(stage_assets)
	}
	stage_file, _ := os.join_path({stage_assets, filename}, context.temp_allocator)
	if write_err := blog_write_atomic_file(stage_file, data); write_err.type != .None {
		return write_err
	}
	if rename_err := os.rename(stage_assets, blog_post_assets_dir(store, slug)); rename_err != nil {
		return Error{type = .Filesystem, msg = fmt.tprintf("Could not commit blog assets: %v", rename_err)}
	}
	stage_exists = false
	return Error{type = .None}
}

load_published_blog_asset :: proc(store: ^Blog_Store, slug, filename: string) -> ([]u8, Error) {
	if !blog_slug_is_valid(slug) || !blog_asset_filename_is_valid(filename) {
		return nil, Error{type = .Validation, msg = "Invalid blog asset path"}
	}

	sync.lock(&store.mu)
	defer sync.unlock(&store.mu)
	meta, meta_err := load_blog_post_metadata_by_slug_unlocked(store, slug)
	if meta_err.type != .None {
		return nil, meta_err
	}
	if meta.status != "published" {
		return nil, Error{type = .Validation, msg = "Blogpost is not published"}
	}

	assets_dir := blog_post_assets_dir(store, slug)
	entry_type, found, entry_err := blog_directory_entry(assets_dir, filename)
	if entry_err.type != .None {
		return nil, entry_err
	}
	if !found || entry_type != .Regular {
		return nil, Error{type = .Validation, msg = "Blog asset does not exist"}
	}
	asset_path, _ := os.join_path({assets_dir, filename}, context.temp_allocator)
	asset_bytes, read_err := os.read_entire_file_from_path(asset_path, context.temp_allocator)
	if read_err != nil {
		return nil, Error{type = .Filesystem, msg = fmt.tprintf("Could not read blog asset: %v", read_err)}
	}
	if !blog_asset_bytes_match_extension(filename, asset_bytes) {
		return nil, Error{type = .Validation, msg = "Blog asset content is invalid"}
	}
	return asset_bytes, Error{type = .None}
}

blog_uploaded_asset_url :: proc(slug, filename: string, allocator := context.temp_allocator) -> string {
	return fmt.tprintf("%s/%s/assets/%s", BLOG_MEDIA_URL_PREFIX, slug, filename)
}

Blog_Post_Form_Data :: struct {
	Title:       string,
	Slug:        string,
	Status:      string,
	Language:     string,
	PublishedAt: string,
	Markdown:    string,
	CreatedAt:   string,
	UpdatedAt:   string,
	IsNew:       bool,
	FormAction:  string,
	PublicUrl:   string,
	CsrfToken:   string,
}

Admin_Blog_List_Item :: struct {
	Title:       string,
	Slug:        string,
	Status:      string,
	UpdatedAt:   string,
	PublishedAt: string,
}
