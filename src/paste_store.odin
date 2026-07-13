package main

import "core:mem"
import "core:strings"
import "core:sync"

PASTE_GIST_FILENAME             :: "sacha-house-paste.json"
PASTE_GIST_DESCRIPTION_PREFIX   :: "sacha.house encrypted paste pid="
PASTE_GIST_PAGE_SIZE            :: 100
PASTE_STORE_MIN_BODY_BYTES      :: 1024
PASTE_STORE_MAX_BODY_BYTES      :: 1024 * 1024
PASTE_STORE_MIN_LIST_ITEMS      :: 1
PASTE_STORE_MAX_LIST_ITEMS      :: 500
PASTE_STORE_MAX_REVISION_BYTES  :: 128

Paste_Service :: struct {
	enabled: bool,
	store:   Paste_Store,
}

// Paste_Store owns its client and keyring. It must remain at a stable address
// after initialization because codec.keys points at keyring. Callers must not
// copy an initialized store or use it after paste_store_destroy.
Paste_Store :: struct {
	gist:           Gist_Client,
	keyring:        Paste_Keyring,
	codec:          Paste_Codec,
	mutations_mu:   sync.Mutex,
	max_body_bytes: int,
	max_list_items: int,
	allocator:      mem.Allocator,
	initialized:    bool,
}

Paste_Input :: struct {
	title: string,
	body:  string,
}

Paste_Loaded :: struct {
	gist_id:        string,
	revision:       string,
	key_id:         string,
	paste_id:       string,
	document:       Paste_Document,
	needs_rotation: bool,
}

Paste_List_Status :: enum {
	Ready,
	Needs_Rotation,
	Unknown_Key,
	Corrupt,
}

Paste_Summary :: struct {
	gist_id:    string,
	revision:   string,
	key_id:     string,
	paste_id:   string,
	title:      string,
	created_at: string,
	updated_at: string,
	status:     Paste_List_Status,
}

Paste_Error_Kind :: enum {
	None,
	Disabled,
	Invalid_Input,
	Not_Found,
	Not_Ours,
	Conflict,
	Unknown_Key,
	Corrupt,
	Rate_Limited,
	Upstream_Unavailable,
	Too_Large,
	Outcome_Unknown,
}

Paste_Error :: struct {
	kind:                Paste_Error_Kind,
	retry_after_seconds: int,
	message:             string,
}

paste_service_init :: proc(
	service: ^Paste_Service,
	enabled: bool,
	base_url: string,
	secrets: ^Paste_Secrets_Config,
	max_body_bytes, max_list_items: int,
	allocator := context.allocator,
) -> Paste_Error {
	if service == nil || allocator.procedure == nil {
		return paste_error(.Invalid_Input)
	}
	if service.enabled || service.store.initialized || service.store.gist.bearer_token != nil ||
	   service.store.keyring.by_id != nil {
		return paste_error(.Invalid_Input)
	}
	service^ = {}
	if !enabled {
		return {}
	}
	if err := paste_store_init(
		&service.store,
		base_url,
		secrets,
		max_body_bytes,
		max_list_items,
		allocator,
	); err.kind != .None {
		return err
	}
	service.enabled = true
	return {}
}

paste_service_destroy :: proc(service: ^Paste_Service) {
	if service == nil {
		return
	}
	paste_store_destroy(&service.store)
	service^ = {}
}

paste_store_init :: proc(
	store: ^Paste_Store,
	base_url: string,
	secrets: ^Paste_Secrets_Config,
	max_body_bytes, max_list_items: int,
	allocator := context.allocator,
) -> Paste_Error {
	if store == nil || secrets == nil || allocator.procedure == nil ||
	   max_body_bytes < PASTE_STORE_MIN_BODY_BYTES ||
	   max_body_bytes > PASTE_STORE_MAX_BODY_BYTES ||
	   max_list_items < PASTE_STORE_MIN_LIST_ITEMS ||
	   max_list_items > PASTE_STORE_MAX_LIST_ITEMS ||
	   !paste_max_body_is_valid(max_body_bytes) {
		return paste_error(.Invalid_Input)
	}
	if store.initialized || store.gist.bearer_token != nil || store.keyring.by_id != nil {
		return paste_error(.Invalid_Input)
	}

	store^ = {}
	store.allocator = allocator
	store.max_body_bytes = max_body_bytes
	store.max_list_items = max_list_items

	if keyring_err := paste_keyring_init(&store.keyring, secrets, allocator); keyring_err != .None {
		store^ = {}
		return paste_secret_error(keyring_err)
	}
	if codec_err := paste_codec_init(&store.codec, &store.keyring); codec_err != .None {
		paste_keyring_destroy(&store.keyring, allocator)
		store^ = {}
		return paste_codec_error(codec_err)
	}
	if gist_err := gist_client_init(
		&store.gist,
		base_url,
		transmute([]byte)secrets.github_gist_token,
		allocator,
	); gist_err.kind != .None {
		paste_codec_destroy(&store.codec)
		paste_keyring_destroy(&store.keyring, allocator)
		store^ = {}
		return paste_gist_error(gist_err)
	}

	store.initialized = true
	return {}
}

paste_store_destroy :: proc(store: ^Paste_Store) {
	if store == nil {
		return
	}
	if store.gist.bearer_token != nil {
		gist_client_destroy(&store.gist)
	}
	paste_codec_destroy(&store.codec)
	if store.keyring.by_id != nil || store.keyring.owned != nil {
		paste_keyring_destroy(&store.keyring, store.allocator)
	}
	store^ = {}
}

paste_loaded_destroy :: proc(
	loaded: ^Paste_Loaded,
	allocator := context.temp_allocator,
) {
	if loaded == nil {
		return
	}
	paste_document_destroy(&loaded.document, allocator)
	paste_delete_string(loaded.gist_id, allocator)
	paste_delete_string(loaded.revision, allocator)
	paste_delete_string(loaded.key_id, allocator)
	paste_delete_string(loaded.paste_id, allocator)
	loaded^ = {}
}

paste_summaries_destroy :: proc(
	items: []Paste_Summary,
	allocator := context.temp_allocator,
) {
	for &item in items {
		paste_summary_destroy(&item, allocator)
	}
	if items != nil {
		delete(items, allocator)
	}
}

paste_store_validate_input :: proc(
	store: ^Paste_Store,
	input: Paste_Input,
	now_ms: i64,
) -> Paste_Error {
	if !paste_store_ready(store) {
		return paste_error(.Disabled)
	}
	if input_err := paste_document_fields_are_valid(
		input.title,
		input.body,
		now_ms,
		now_ms,
		store.max_body_bytes,
	); input_err != .None {
		return paste_codec_error(input_err)
	}
	return {}
}

@(private)
paste_summary_buffer_destroy :: proc(
	buffer: ^[dynamic]Paste_Summary,
	allocator: mem.Allocator,
) {
	if buffer == nil {
		return
	}
	for &item in buffer^ {
		paste_summary_destroy(&item, allocator)
	}
	if buffer^ != nil {
		delete(buffer^)
	}
	buffer^ = nil
}

@(private)
paste_summary_buffer_release :: proc(
	buffer: ^[dynamic]Paste_Summary,
	allocator: mem.Allocator,
) -> ([]Paste_Summary, bool) {
	if buffer == nil {
		return nil, false
	}
	if len(buffer^) == 0 {
		if buffer^ != nil {
			delete(buffer^)
		}
		buffer^ = nil
		return nil, true
	}
	items, alloc_err := make([]Paste_Summary, len(buffer^), allocator)
	if alloc_err != nil {
		return nil, false
	}
	copy(items, buffer^[:])
	delete(buffer^)
	buffer^ = nil
	return items, true
}

paste_store_list :: proc(
	store: ^Paste_Store,
	allocator := context.temp_allocator,
) -> (items: []Paste_Summary, truncated: bool, err: Paste_Error) {
	if !paste_store_ready(store) {
		return nil, false, paste_error(.Disabled)
	}
	if allocator.procedure == nil {
		return nil, false, paste_error(.Invalid_Input)
	}

	result, alloc_err := make([dynamic]Paste_Summary, 0, store.max_list_items, allocator)
	if alloc_err != nil {
		return nil, false, paste_error(.Upstream_Unavailable)
	}
	committed := false
	defer if !committed {
		paste_summary_buffer_destroy(&result, allocator)
	}

	examined := 0
	page := 1
	for examined < store.max_list_items {
		per_page := min(PASTE_GIST_PAGE_SIZE, store.max_list_items - examined)
		gists, gist_err := gist_list(&store.gist, page, per_page, allocator)
		if gist_err.kind != .None {
			items, release_ok := paste_summary_buffer_release(&result, allocator)
			if !release_ok {
				return nil, true, paste_error(.Upstream_Unavailable)
			}
			committed = true
			return items, true, paste_gist_error(gist_err)
		}
		defer paste_gists_destroy(gists, allocator)

		for &gist in gists {
			examined += 1
			summary, include, summary_err := paste_store_summarize_gist(store, &gist, allocator)
			if summary_err.kind != .None {
				released_items, release_ok := paste_summary_buffer_release(&result, allocator)
				if !release_ok {
					return nil, true, paste_error(.Upstream_Unavailable)
				}
				committed = true
				return released_items, true, summary_err
			}
			if include {
				append(&result, summary)
			}
		}

		if len(gists) < per_page {
			released_items, release_ok := paste_summary_buffer_release(&result, allocator)
			if !release_ok {
				return nil, false, paste_error(.Upstream_Unavailable)
			}
			committed = true
			return released_items, false, {}
		}
		page += 1
	}

	released_items, release_ok := paste_summary_buffer_release(&result, allocator)
	if !release_ok {
		return nil, true, paste_error(.Upstream_Unavailable)
	}
	committed = true
	return released_items, true, {}
}

paste_store_get :: proc(
	store: ^Paste_Store,
	gist_id: string,
	allocator := context.temp_allocator,
) -> (Paste_Loaded, Paste_Error) {
	if !paste_store_ready(store) {
		return {}, paste_error(.Disabled)
	}
	if allocator.procedure == nil {
		return {}, paste_error(.Invalid_Input)
	}
	if !paste_gist_id_is_valid(gist_id) {
		return {}, paste_error(.Not_Found)
	}

	gist, gist_err := gist_get(&store.gist, gist_id, allocator)
	if gist_err.kind != .None {
		return {}, paste_gist_error(gist_err)
	}
	defer paste_gist_destroy(&gist, allocator)
	if !paste_same_gist_id(gist.id, gist_id) {
		return {}, paste_error(.Upstream_Unavailable)
	}
	return paste_loaded_from_gist(store, &gist, allocator)
}

paste_store_create :: proc(
	store: ^Paste_Store,
	input: Paste_Input,
	now_ms: i64,
	allocator := context.temp_allocator,
) -> (Paste_Loaded, Paste_Error) {
	if !paste_store_ready(store) {
		return {}, paste_error(.Disabled)
	}
	if allocator.procedure == nil {
		return {}, paste_error(.Invalid_Input)
	}
	if input_err := paste_store_validate_input(store, input, now_ms); input_err.kind != .None {
		return {}, input_err
	}

	envelope, pid, codec_err := paste_encrypt_new(
		&store.codec,
		input.title,
		input.body,
		now_ms,
		store.max_body_bytes,
		allocator,
	)
	if codec_err != .None {
		return {}, paste_codec_error(codec_err)
	}
	defer {
		paste_wipe_string(envelope)
		paste_delete_string(envelope, allocator)
		paste_wipe_string(pid)
		paste_delete_string(pid, allocator)
	}

	description_storage: [len(PASTE_GIST_DESCRIPTION_PREFIX) + PASTE_PID_BYTES * 2]byte
	description := paste_fill_description(&description_storage, pid)
	if description == "" {
		return {}, paste_error(.Corrupt)
	}
	files := make(map[string]Gist_Write_File, allocator)
	defer delete(files)
	files[PASTE_GIST_FILENAME] = Gist_Write_File{content = envelope}
	request := Gist_Create_Request {
		description = description,
		public      = false,
		files       = files,
	}

	created, gist_err := gist_create(&store.gist, &request, allocator)
	if gist_err.kind != .None {
		return {}, paste_gist_error(gist_err)
	}
	defer paste_gist_destroy(&created, allocator)
	loaded, load_err := paste_loaded_after_mutation(store, &created, allocator)
	if load_err.kind != .None {
		return {}, load_err
	}
	if loaded.paste_id != pid {
		paste_loaded_destroy(&loaded, allocator)
		return {}, paste_error(.Upstream_Unavailable)
	}
	return loaded, {}
}

paste_store_update :: proc(
	store: ^Paste_Store,
	gist_id, expected_revision: string,
	input: Paste_Input,
	now_ms: i64,
	allocator := context.temp_allocator,
) -> (Paste_Loaded, Paste_Error) {
	if !paste_store_ready(store) {
		return {}, paste_error(.Disabled)
	}
	if allocator.procedure == nil || !paste_revision_is_valid(expected_revision) {
		return {}, paste_error(.Invalid_Input)
	}
	if !paste_gist_id_is_valid(gist_id) {
		return {}, paste_error(.Not_Found)
	}
	if input_err := paste_store_validate_input(store, input, now_ms); input_err.kind != .None {
		return {}, input_err
	}

	// GitHub does not provide an atomic conditional PATCH for Gists. This lock
	// serializes the supported single-process writer; the GET/revision/PATCH
	// sequence must not be described as cross-provider compare-and-swap.
	sync.lock(&store.mutations_mu)
	defer sync.unlock(&store.mutations_mu)

	current, current_err := paste_store_get(store, gist_id, allocator)
	if current_err.kind != .None {
		return {}, current_err
	}
	defer paste_loaded_destroy(&current, allocator)
	if current.revision != expected_revision {
		return {}, paste_error(.Conflict)
	}
	if now_ms < current.document.created_ms {
		return {}, paste_error(.Invalid_Input)
	}

	current.document.title = input.title
	current.document.body = input.body
	current.document.updated_ms = now_ms
	envelope, codec_err := paste_encrypt_existing(
		&store.codec,
		current.paste_id,
		&current.document,
		store.max_body_bytes,
		allocator,
	)
	if codec_err != .None {
		return {}, paste_codec_error(codec_err)
	}
	defer {
		paste_wipe_string(envelope)
		paste_delete_string(envelope, allocator)
	}
	return paste_store_write_envelope(store, gist_id, envelope, allocator)
}

paste_store_rotate :: proc(
	store: ^Paste_Store,
	gist_id, expected_revision: string,
	allocator := context.temp_allocator,
) -> (Paste_Loaded, Paste_Error) {
	if !paste_store_ready(store) {
		return {}, paste_error(.Disabled)
	}
	if allocator.procedure == nil || !paste_revision_is_valid(expected_revision) {
		return {}, paste_error(.Invalid_Input)
	}
	if !paste_gist_id_is_valid(gist_id) {
		return {}, paste_error(.Not_Found)
	}

	sync.lock(&store.mutations_mu)
	defer sync.unlock(&store.mutations_mu)

	current, current_err := paste_store_get(store, gist_id, allocator)
	if current_err.kind != .None {
		return {}, current_err
	}
	defer paste_loaded_destroy(&current, allocator)
	if current.revision != expected_revision {
		return {}, paste_error(.Conflict)
	}

	// Re-encryption uses the active key and a new nonce while retaining both
	// semantic timestamps and the stable pid.
	envelope, codec_err := paste_encrypt_existing(
		&store.codec,
		current.paste_id,
		&current.document,
		store.max_body_bytes,
		allocator,
	)
	if codec_err != .None {
		return {}, paste_codec_error(codec_err)
	}
	defer {
		paste_wipe_string(envelope)
		paste_delete_string(envelope, allocator)
	}
	return paste_store_write_envelope(store, gist_id, envelope, allocator)
}

paste_store_delete :: proc(
	store: ^Paste_Store,
	gist_id, expected_revision: string,
) -> Paste_Error {
	if !paste_store_ready(store) {
		return paste_error(.Disabled)
	}
	if !paste_revision_is_valid(expected_revision) {
		return paste_error(.Invalid_Input)
	}
	if !paste_gist_id_is_valid(gist_id) {
		return paste_error(.Not_Found)
	}

	sync.lock(&store.mutations_mu)
	defer sync.unlock(&store.mutations_mu)

	current, current_err := paste_store_get(store, gist_id, context.temp_allocator)
	if current_err.kind != .None {
		return current_err
	}
	defer paste_loaded_destroy(&current, context.temp_allocator)
	if current.revision != expected_revision {
		return paste_error(.Conflict)
	}
	return paste_gist_error(gist_delete(&store.gist, gist_id))
}

@(private)
paste_store_write_envelope :: proc(
	store: ^Paste_Store,
	gist_id, envelope: string,
	allocator: mem.Allocator,
) -> (Paste_Loaded, Paste_Error) {
	files := make(map[string]Gist_Write_File, allocator)
	defer delete(files)
	files[PASTE_GIST_FILENAME] = Gist_Write_File{content = envelope}
	request := Gist_Update_Request{files = files}

	updated, gist_err := gist_update(&store.gist, gist_id, &request, allocator)
	if gist_err.kind != .None {
		return {}, paste_gist_error(gist_err)
	}
	defer paste_gist_destroy(&updated, allocator)
	if !paste_same_gist_id(updated.id, gist_id) {
		return {}, paste_error(.Upstream_Unavailable)
	}
	return paste_loaded_after_mutation(store, &updated, allocator)
}

@(private)
paste_loaded_after_mutation :: proc(
	store: ^Paste_Store,
	gist: ^Gist,
	allocator: mem.Allocator,
) -> (Paste_Loaded, Paste_Error) {
	_, _, ours := paste_gist_owner(gist)
	if !ours {
		return {}, paste_error(.Upstream_Unavailable)
	}
	file := gist.files[PASTE_GIST_FILENAME]
	if file.truncated || file.content == "" || len(gist.history) == 0 {
		fetched, fetch_err := gist_get(&store.gist, gist.id, allocator)
		if fetch_err.kind != .None {
			return {}, paste_gist_error(fetch_err)
		}
		defer paste_gist_destroy(&fetched, allocator)
		if !paste_same_gist_id(fetched.id, gist.id) {
			return {}, paste_error(.Upstream_Unavailable)
		}
		return paste_loaded_from_gist(store, &fetched, allocator)
	}
	return paste_loaded_from_gist(store, gist, allocator)
}

@(private)
paste_loaded_from_gist :: proc(
	store: ^Paste_Store,
	gist: ^Gist,
	allocator: mem.Allocator,
) -> (Paste_Loaded, Paste_Error) {
	marker_pid, file, ours := paste_gist_owner(gist)
	if !ours {
		return {}, paste_error(.Not_Ours)
	}
	if file.truncated {
		return {}, paste_error(.Too_Large)
	}
	if file.content == "" {
		return {}, paste_error(.Corrupt)
	}
	revision, revision_ok := paste_gist_revision(gist)
	if !revision_ok {
		return {}, paste_error(.Corrupt)
	}

	doc, envelope, codec_err := paste_decrypt(
		&store.codec,
		file.content,
		store.max_body_bytes,
		allocator,
	)
	defer paste_document_destroy(&doc, allocator)
	if envelope.pid != "" && envelope.pid != marker_pid {
		return {}, paste_error(.Not_Ours)
	}
	if codec_err != .None {
		return {}, paste_codec_error(codec_err)
	}
	if envelope.pid != marker_pid {
		return {}, paste_error(.Not_Ours)
	}

	loaded: Paste_Loaded
	clone_ok: bool
	loaded.gist_id, clone_ok = paste_clone_string(gist.id, allocator)
	if !clone_ok do return {}, paste_error(.Upstream_Unavailable)
	loaded.revision, clone_ok = paste_clone_string(revision, allocator)
	if !clone_ok {
		paste_loaded_destroy(&loaded, allocator)
		return {}, paste_error(.Upstream_Unavailable)
	}
	loaded.key_id, clone_ok = paste_clone_string(envelope.kid, allocator)
	if !clone_ok {
		paste_loaded_destroy(&loaded, allocator)
		return {}, paste_error(.Upstream_Unavailable)
	}
	loaded.paste_id, clone_ok = paste_clone_string(envelope.pid, allocator)
	if !clone_ok {
		paste_loaded_destroy(&loaded, allocator)
		return {}, paste_error(.Upstream_Unavailable)
	}
	loaded.needs_rotation = envelope.kid != store.keyring.active.id
	loaded.document = doc
	doc = {}
	return loaded, {}
}

@(private)
paste_store_summarize_gist :: proc(
	store: ^Paste_Store,
	listed: ^Gist,
	allocator: mem.Allocator,
) -> (Paste_Summary, bool, Paste_Error) {
	listed_pid, listed_file, listed_ours := paste_gist_owner(listed)
	if !listed_ours {
		return {}, false, {}
	}

	source := listed
	fetched: Gist
	defer paste_gist_destroy(&fetched, allocator)
	if listed_file.truncated || listed_file.content == "" || len(listed.history) == 0 {
		fetch_err: Gist_Error
		fetched, fetch_err = gist_get(&store.gist, listed.id, allocator)
		if fetch_err.kind != .None {
			return {}, false, paste_gist_error(fetch_err)
		}
		fetched_pid, _, fetched_ours := paste_gist_owner(&fetched)
		if !paste_same_gist_id(fetched.id, listed.id) || !fetched_ours || fetched_pid != listed_pid {
			return {}, false, {}
		}
		source = &fetched
	}

	marker_pid, file, ours := paste_gist_owner(source)
	if !ours {
		return {}, false, {}
	}
	revision, revision_ok := paste_gist_revision(source)
	if !revision_ok || file.truncated || file.content == "" {
		summary, ok := paste_make_summary(source, "", marker_pid, "", "", .Corrupt, allocator)
		return summary, ok, paste_error(.Upstream_Unavailable) if !ok else Paste_Error{}
	}

	doc, envelope, codec_err := paste_decrypt(
		&store.codec,
		file.content,
		store.max_body_bytes,
		allocator,
	)
	defer paste_document_destroy(&doc, allocator)
	if codec_err == .Allocation || codec_err == .Invalid_Input {
		return {}, false, paste_error(.Upstream_Unavailable)
	}

	status := Paste_List_Status.Corrupt
	title := ""
	key_id := ""
	if paste_key_id_is_valid(envelope.kid) {
		key_id = envelope.kid
	}
	if codec_err == .Key_Unavailable && envelope.pid == marker_pid {
		status = .Unknown_Key
	} else if codec_err == .None && envelope.pid == marker_pid {
		title = doc.title
		status = .Ready if envelope.kid == store.keyring.active.id else .Needs_Rotation
	}

	summary, ok := paste_make_summary(
		source,
		revision,
		marker_pid,
		key_id,
		title,
		status,
		allocator,
	)
	if !ok {
		return {}, false, paste_error(.Upstream_Unavailable)
	}
	return summary, true, {}
}

@(private)
paste_make_summary :: proc(
	gist: ^Gist,
	revision, paste_id, key_id, title: string,
	status: Paste_List_Status,
	allocator: mem.Allocator,
) -> (Paste_Summary, bool) {
	summary := Paste_Summary{status = status}
	ok: bool
	summary.gist_id, ok = paste_clone_string(gist.id, allocator)
	if !ok do return {}, false
	summary.revision, ok = paste_clone_string(revision, allocator)
	if !ok {
		paste_summary_destroy(&summary, allocator)
		return {}, false
	}
	summary.key_id, ok = paste_clone_string(key_id, allocator)
	if !ok {
		paste_summary_destroy(&summary, allocator)
		return {}, false
	}
	summary.paste_id, ok = paste_clone_string(paste_id, allocator)
	if !ok {
		paste_summary_destroy(&summary, allocator)
		return {}, false
	}
	summary.title, ok = paste_clone_string(title, allocator)
	if !ok {
		paste_summary_destroy(&summary, allocator)
		return {}, false
	}
	summary.created_at, ok = paste_clone_string(gist.created_at, allocator)
	if !ok {
		paste_summary_destroy(&summary, allocator)
		return {}, false
	}
	summary.updated_at, ok = paste_clone_string(gist.updated_at, allocator)
	if !ok {
		paste_summary_destroy(&summary, allocator)
		return {}, false
	}
	return summary, true
}

@(private)
paste_summary_destroy :: proc(summary: ^Paste_Summary, allocator: mem.Allocator) {
	if summary == nil {
		return
	}
	paste_delete_string(summary.gist_id, allocator)
	paste_delete_string(summary.revision, allocator)
	paste_delete_string(summary.key_id, allocator)
	paste_delete_string(summary.paste_id, allocator)
	paste_wipe_string(summary.title)
	paste_delete_string(summary.title, allocator)
	paste_delete_string(summary.created_at, allocator)
	paste_delete_string(summary.updated_at, allocator)
	summary^ = {}
}

@(private)
paste_gist_owner :: proc(gist: ^Gist) -> (pid: string, file: Gist_File, ours: bool) {
	if gist == nil || !paste_gist_id_is_valid(gist.id) || len(gist.files) != 1 {
		return
	}
	description_pid, marker_ok := paste_description_pid(gist.description)
	if !marker_ok {
		return "", {}, false
	}
	gist_file, found := gist.files[PASTE_GIST_FILENAME]
	if !found || gist_file.filename != PASTE_GIST_FILENAME {
		return "", {}, false
	}
	return description_pid, gist_file, true
}

@(private)
paste_description_pid :: proc(description: string) -> (string, bool) {
	expected_length := len(PASTE_GIST_DESCRIPTION_PREFIX) + PASTE_PID_BYTES * 2
	if len(description) != expected_length ||
	   description[:len(PASTE_GIST_DESCRIPTION_PREFIX)] != PASTE_GIST_DESCRIPTION_PREFIX {
		return "", false
	}
	pid := description[len(PASTE_GIST_DESCRIPTION_PREFIX):]
	return pid, paste_lower_hex_is_valid(pid, PASTE_PID_BYTES * 2)
}

@(private)
paste_fill_description :: proc(
	storage: ^[len(PASTE_GIST_DESCRIPTION_PREFIX) + PASTE_PID_BYTES * 2]byte,
	pid: string,
) -> string {
	if storage == nil || !paste_lower_hex_is_valid(pid, PASTE_PID_BYTES * 2) {
		return ""
	}
	copy(storage[:len(PASTE_GIST_DESCRIPTION_PREFIX)], PASTE_GIST_DESCRIPTION_PREFIX)
	copy(storage[len(PASTE_GIST_DESCRIPTION_PREFIX):], transmute([]byte)pid)
	return string(storage[:])
}

@(private)
paste_gist_revision :: proc(gist: ^Gist) -> (string, bool) {
	if gist == nil || len(gist.history) < 1 || !paste_revision_is_valid(gist.history[0].version) {
		return "", false
	}
	return gist.history[0].version, true
}

@(private)
paste_revision_is_valid :: proc(revision: string) -> bool {
	if len(revision) < 1 || len(revision) > PASTE_STORE_MAX_REVISION_BYTES {
		return false
	}
	for c in transmute([]byte)revision {
		switch c {
		case '0'..='9', 'a'..='f', 'A'..='F':
		case:
			return false
		}
	}
	return true
}

@(private)
paste_gist_id_is_valid :: proc(id: string) -> bool {
	if len(id) < 1 || len(id) > GIST_MAX_ID_BYTES {
		return false
	}
	for c in transmute([]byte)id {
		switch c {
		case '0'..='9', 'a'..='f', 'A'..='F':
		case:
			return false
		}
	}
	return true
}

@(private)
paste_same_gist_id :: proc(a, b: string) -> bool {
	return paste_gist_id_is_valid(a) && paste_gist_id_is_valid(b) && strings.equal_fold(a, b)
}

@(private)
paste_store_ready :: proc(store: ^Paste_Store) -> bool {
	return store != nil &&
		store.initialized &&
		store.allocator.procedure != nil &&
		store.max_body_bytes >= PASTE_STORE_MIN_BODY_BYTES &&
		store.max_body_bytes <= PASTE_STORE_MAX_BODY_BYTES &&
		store.max_list_items >= PASTE_STORE_MIN_LIST_ITEMS &&
		store.max_list_items <= PASTE_STORE_MAX_LIST_ITEMS &&
		store.codec.keys == &store.keyring &&
		store.keyring.active != nil &&
		store.gist.bearer_token != nil
}

@(private)
paste_clone_string :: proc(value: string, allocator: mem.Allocator) -> (string, bool) {
	if value == "" {
		return "", true
	}
	cloned, alloc_err := strings.clone(value, allocator)
	return cloned, alloc_err == .None
}

@(private)
paste_delete_string :: proc(value: string, allocator: mem.Allocator) {
	if value != "" {
		delete(value, allocator)
	}
}

@(private)
paste_gists_destroy :: proc(gists: []Gist, allocator: mem.Allocator) {
	for &gist in gists {
		paste_gist_destroy(&gist, allocator)
	}
	if gists != nil {
		delete(gists, allocator)
	}
}

@(private)
paste_gist_destroy :: proc(gist: ^Gist, allocator: mem.Allocator) {
	if gist == nil {
		return
	}
	paste_delete_string(gist.id, allocator)
	paste_delete_string(gist.description, allocator)
	paste_delete_string(gist.created_at, allocator)
	paste_delete_string(gist.updated_at, allocator)
	if gist.files != nil {
		for filename, file in gist.files {
			paste_delete_string(filename, allocator)
			paste_delete_string(file.filename, allocator)
			paste_delete_string(file.raw_url, allocator)
			paste_delete_string(file.content, allocator)
		}
		delete(gist.files)
	}
	for &history in gist.history {
		paste_delete_string(history.version, allocator)
		paste_delete_string(history.committed_at, allocator)
	}
	if gist.history != nil {
		delete(gist.history, allocator)
	}
	gist^ = {}
}

@(private)
paste_secret_error :: proc(err: Paste_Secrets_Error) -> Paste_Error {
	switch err {
	case .None:
		return {}
	case .Invalid_JSON, .Invalid_Shape, .Empty_Token, .Invalid_Key_Count,
	     .Invalid_Key_Id, .Duplicate_Key_Id, .Duplicate_Key_Material,
	     .Invalid_Key_Material, .Missing_Active_Key:
		return paste_error(.Invalid_Input)
	case .Allocation:
		return paste_error(.Upstream_Unavailable)
	}
	return paste_error(.Upstream_Unavailable)
}

@(private)
paste_codec_error :: proc(err: Paste_Codec_Error) -> Paste_Error {
	switch err {
	case .None:
		return {}
	case .Invalid_Input:
		return paste_error(.Invalid_Input)
	case .Too_Large:
		return paste_error(.Too_Large)
	case .Key_Unavailable:
		return paste_error(.Unknown_Key)
	case .Invalid_Envelope, .Unsupported_Version, .Unsupported_Algorithm, .Authentication_Failed:
		return paste_error(.Corrupt)
	case .Allocation:
		return paste_error(.Upstream_Unavailable)
	}
	return paste_error(.Upstream_Unavailable)
}

@(private)
paste_gist_error :: proc(err: Gist_Error) -> Paste_Error {
	switch err.kind {
	case .None:
		return {}
	case .Not_Found:
		return paste_error(.Not_Found)
	case .Rate_Limited:
		return Paste_Error {
			kind                = .Rate_Limited,
			retry_after_seconds = err.retry_after_seconds,
			message             = "paste storage is rate limited",
		}
	case .Response_Too_Large:
		return paste_error(.Too_Large)
	case .Outcome_Unknown:
		return paste_error(.Outcome_Unknown)
	case .Network, .Timeout, .TLS, .Unauthorized, .Forbidden,
	     .Validation, .Malformed_Response, .Upstream:
		return paste_error(.Upstream_Unavailable)
	}
	return paste_error(.Upstream_Unavailable)
}

@(private)
paste_error :: proc(kind: Paste_Error_Kind) -> Paste_Error {
	message := "paste storage unavailable"
	switch kind {
	case .None:
		message = ""
	case .Disabled:
		message = "encrypted paste storage is disabled"
	case .Invalid_Input:
		message = "invalid paste input"
	case .Not_Found:
		message = "paste not found"
	case .Not_Ours:
		message = "Gist is not an encrypted paste"
	case .Conflict:
		message = "remote revision changed; reload before saving"
	case .Unknown_Key:
		message = "paste encryption key is unavailable"
	case .Corrupt:
		message = "encrypted paste could not be authenticated"
	case .Rate_Limited:
		message = "paste storage is rate limited"
	case .Upstream_Unavailable:
		message = "paste storage is unavailable"
	case .Too_Large:
		message = "paste data exceeds the configured limit"
	case .Outcome_Unknown:
		message = "the remote mutation outcome is unknown; refresh before retrying"
	}
	return Paste_Error{kind = kind, message = message}
}
