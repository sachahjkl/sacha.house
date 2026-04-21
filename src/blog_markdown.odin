package main

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"
import "core:unicode"
import commonmark "vendor:commonmark"


normalize_markdown_newlines :: proc(markdown: string, allocator := context.temp_allocator) -> string {
	res, _ := strings.replace_all(markdown, "\r\n", "\n", allocator)
	res, _ = strings.replace_all(res, "\r", "\n", allocator)
	return res
}

append_excerpt_segment :: proc(sb: ^strings.Builder, s: string, pending_space: ^bool, remaining: ^int) {
	for r in s {
		if remaining^ == 0 {
			return
		}

		if unicode.is_space(r) {
			pending_space^ = true
			continue
		}

		if pending_space^ && strings.builder_len(sb^) > 0 {
			strings.write_byte(sb, ' ')
			pending_space^ = false
			if remaining^ > 0 {
				remaining^ -= 1
				if remaining^ == 0 {
					return
				}
			}
		}

		strings.write_rune(sb, r)
		pending_space^ = false
		if remaining^ > 0 {
			remaining^ -= 1
		}
	}
}

truncate_plain_text_at_word_boundary :: proc(text: string, max_chars: int, allocator := context.temp_allocator) -> string {
	trimmed := strings.trim_space(text)
	if max_chars <= 0 || strings.rune_count(trimmed) <= max_chars {
		return trimmed
	}

	sb := strings.builder_make(allocator)
	defer strings.builder_destroy(&sb)

	rune_count := 0
	last_space_len := -1
	for r in trimmed {
		if rune_count == max_chars {
			break
		}
		strings.write_rune(&sb, r)
		rune_count += 1
		if unicode.is_space(r) {
			last_space_len = strings.builder_len(sb)
		}
	}

	truncated := strings.to_string(sb)
	if last_space_len > 0 {
		truncated = truncated[:last_space_len]
	}
	truncated = strings.trim_space(truncated)
	if truncated == "" {
		truncated = strings.trim_space(strings.to_string(sb))
	}
	return fmt.tprintf("%s...", truncated)
}

markdown_text_content :: proc(markdown: string, max_chars := -1, allocator := context.temp_allocator) -> string {
	normalized := normalize_markdown_newlines(markdown, allocator)
	root := commonmark.parse_document(raw_data(normalized), len(normalized), commonmark.DEFAULT_OPTIONS)
	if root == nil {
		return strings.trim_space(normalized)
	}
	defer commonmark.node_free(root)

	iter := commonmark.iter_new(root)
	if iter == nil {
		return strings.trim_space(normalized)
	}
	defer commonmark.iter_free(iter)

	sb := strings.builder_make(allocator)
	defer strings.builder_destroy(&sb)
	pending_space := false
	remaining := max_chars
	skip_image_depth := 0

	for {
		event := commonmark.iter_next(iter)
		if event == .Done {
			break
		}

		node := commonmark.iter_get_node(iter)
		if node == nil {
			continue
		}

		node_type := commonmark.node_get_type(node)
		if node_type == .Image {
			if event == .Enter {
				skip_image_depth += 1
				pending_space = true
			} else if event == .Exit {
				skip_image_depth -= 1
			}
			continue
		}

		if skip_image_depth > 0 {
			continue
		}

		#partial switch node_type {
		case .Text, .Code, .Code_Block:
			if event != .Enter {
				continue
			}
			literal := commonmark.node_get_literal(node)
			if literal != nil {
				append_excerpt_segment(&sb, string(literal), &pending_space, &remaining)
			}
		case .Soft_Break, .Line_Break, .Paragraph, .Heading, .Item, .Block_Quote, .List, .Thematic_Break:
			pending_space = true
		case:
		}

		if remaining == 0 {
			break
		}
	}

	return strings.trim_space(strings.to_string(sb))
}

markdown_to_plain_text :: proc(markdown: string, allocator := context.temp_allocator) -> string {
	return markdown_text_content(markdown, -1, allocator)
}

excerpt_from_plain_text :: proc(text: string, max_chars := 180, allocator := context.temp_allocator) -> string {
	return truncate_plain_text_at_word_boundary(text, max_chars, allocator)
}

markdown_to_excerpt :: proc(markdown: string, max_chars := 180, allocator := context.temp_allocator) -> string {
	plain_text := markdown_text_content(markdown, -1, allocator)
	return truncate_plain_text_at_word_boundary(plain_text, max_chars, allocator)
}

datetime_local_to_utc_rfc3339 :: proc(value: string, tz: ^datetime.TZ_Region, allocator := context.temp_allocator) -> string {
	trimmed := strings.trim_space(value)
	if trimmed == "" {
		return ""
	}
	if len(trimmed) != len("2006-01-02T15:04") {
		return ""
	}

	year, ok_year := strconv.parse_int(trimmed[0:4])
	if !ok_year || trimmed[4] != '-' {
		return ""
	}
	month, ok_month := strconv.parse_int(trimmed[5:7])
	if !ok_month || trimmed[7] != '-' {
		return ""
	}
	day, ok_day := strconv.parse_int(trimmed[8:10])
	if !ok_day || trimmed[10] != 'T' {
		return ""
	}
	hour, ok_hour := strconv.parse_int(trimmed[11:13])
	if !ok_hour || trimmed[13] != ':' {
		return ""
	}
	minute, ok_minute := strconv.parse_int(trimmed[14:16])
	if !ok_minute {
		return ""
	}

	local_dt := datetime.DateTime{
		year   = i64(year),
		month  = i8(month),
		day    = i8(day),
		hour   = i8(hour),
		minute = i8(minute),
		second = 0,
		nano   = 0,
		tz     = tz,
	}
	utc_dt, ok_utc_dt := timezone.datetime_to_utc(local_dt)
	if !ok_utc_dt {
		return ""
	}
	utc_tm, ok_utc_tm := time.datetime_to_time(utc_dt)
	if !ok_utc_tm {
		return ""
	}
	res, _ := time.time_to_rfc3339(utc_tm, 0, false, allocator)
	return res
}

markdown_to_html :: proc(markdown: string, allocator := context.temp_allocator) -> string {
	normalized := normalize_markdown_newlines(markdown, allocator)
	html := commonmark.markdown_to_html(cstring(raw_data(normalized)), len(normalized), commonmark.DEFAULT_OPTIONS)
	if html == nil {
		return normalized
	}
	defer commonmark.free(html)
	return strings.clone(string(html), allocator) or_else string(html)
}
