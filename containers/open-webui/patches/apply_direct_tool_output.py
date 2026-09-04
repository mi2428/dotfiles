"""Patch pinned Open WebUI middleware for declarative tools and direct research output.

The upstream middleware normally feeds external tool results back to the model. Deep
Research instead marks exact Markdown for direct display; this patch stores that report as
a private Note and completes the assistant message without another model turn. Exact-match
guards fail the image build when the pinned Open WebUI middleware changes unexpectedly.
"""

from pathlib import Path

REPLACEMENTS: list[tuple[str, str]] = []


def add_replacement(old: str, new: str) -> None:
    REPLACEMENTS.append((old, new))


def replace_once(source: str, old: str, new: str) -> str:
    """Replace one pinned upstream fragment or fail closed on version drift."""
    if source.count(old) != 1:
        raise RuntimeError(f"OpenWebUI middleware patch guard failed: {old[:80]!r}")
    return source.replace(old, new)


add_replacement(
    """    tool_ids = form_data.pop('tool_ids', None)
    terminal_id = form_data.pop('terminal_id', None)
""",
    """    tool_ids = form_data.pop('tool_ids', None)
    # dotfiles: UI requests inherit declarative model tools when omitted
    if tool_ids is None and metadata.get('session_id'):
        tool_ids = model.get('info', {}).get('meta', {}).get('toolIds', [])
    terminal_id = form_data.pop('terminal_id', None)
""",
)


add_replacement(
    "from open_webui.models.notes import Notes",
    "from open_webui.models.notes import NoteForm, NoteUpdateForm, Notes\n"
    "from open_webui.utils.deep_research_notes import persist_deep_research_note",
)


add_replacement(
    """                all_tool_call_sources = []  # Accumulated sources across all iterations
                user_message = get_last_user_message(form_data['messages'])
""",
    """                all_tool_call_sources = []  # Accumulated sources across all iterations
                direct_tool_output = None
                user_message = get_last_user_message(form_data['messages'])
""",
)
add_replacement(
    """                        tool_function_params, tool_result, tool, tool_type, direct_tool = tool_results[id(tool_call)]
                        if tool_result is None:
""",
    """                        tool_function_params, tool_result, tool, tool_type, direct_tool = tool_results[id(tool_call)]
                        tool_response_headers = (
                            tool_result[1]
                            if tool_type == 'external'
                            and isinstance(tool_result, tuple)
                            and len(tool_result) == 2
                            else None
                        )
                        tool_response_header_items = (
                            {str(key).casefold(): str(value) for key, value in tool_response_headers.items()}
                            if tool_response_headers is not None
                            else {}
                        )
                        return_direct = bool(
                            tool_response_header_items.get('x-openwebui-direct-output', '').casefold() == 'true'
                            and tool_response_header_items.get('content-type', '').casefold().startswith('text/plain')
                        )
                        deep_research_status = tool_response_header_items.get('x-deep-research-status', '').casefold()
                        if tool_result is None:
""",
)
add_replacement(
    """                                'content': tool_result_content(tool_result),
                                **({'files': tool_result_files} if tool_result_files else {}),
""",
    """                                'content': tool_result_content(tool_result),
                                'return_direct': return_direct,
                                'deep_research_status': deep_research_status,
                                **({'files': tool_result_files} if tool_result_files else {}),
""",
)
add_replacement(
    """                    # Emit citation sources to the frontend for display
                    if citations_enabled:
""",
    """                    # dotfiles: trusted external tool direct output
                    direct_results = [result for result in results if result.get('return_direct')]
                    if direct_results:
                        if len(direct_results) != 1 or len(results) != 1:
                            await emit_message_error('Direct tool output requires exactly one tool call.')
                            tool_calls.clear()
                            break
                        direct_tool_output = direct_results[0].get('content', '')
                        if not isinstance(direct_tool_output, str) or not direct_tool_output:
                            await emit_message_error('Direct tool output must be non-empty text.')
                            tool_calls.clear()
                            break
                        if direct_results[0].get('deep_research_status') != 'failed':
                            try:
                                deep_research_chat_id = str(metadata.get('chat_id') or '')
                                chat_title = await Chats.get_chat_title_by_id(deep_research_chat_id)
                                await persist_deep_research_note(
                                    notes=Notes,
                                    note_form=NoteForm,
                                    note_update_form=NoteUpdateForm,
                                    user_id=user.id,
                                    message_id=str(metadata.get('message_id') or ''),
                                    chat_id=deep_research_chat_id,
                                    chat_title=str(chat_title or ''),
                                    markdown=direct_tool_output,
                                    user_message=str(user_message or ''),
                                )
                            except Exception:
                                log.exception('Failed to persist Deep Research Note')
                                direct_tool_output = None
                                await emit_message_error('Deep ResearchのNote保存に失敗しました。')
                                tool_calls.clear()
                                break
                        content_parts[:] = [direct_tool_output]
                        output[:] = [item for item in output if item.get('type') != 'message']
                        output.append(
                            {
                                'type': 'message',
                                'id': output_id('msg'),
                                'status': 'completed',
                                'role': 'assistant',
                                'content': [{'type': 'output_text', 'text': direct_tool_output}],
                            }
                        )
                        tool_calls.clear()
                        break

                    # Emit citation sources to the frontend for display
                    if citations_enabled:
""",
)
add_replacement(
    """                            'done': True,
                            'output': current_output,
                            **({'usage': usage} if usage else {}),
""",
    """                            'done': True,
                            'output': current_output,
                            **({'content': direct_tool_output} if direct_tool_output is not None else {}),
                            **({'usage': usage} if usage else {}),
""",
)


def patch_middleware(source: str) -> str:
    """Apply all guarded changes to the pinned middleware source."""
    for old, new in REPLACEMENTS:
        source = replace_once(source, old, new)
    return source


def main() -> None:
    """Patch and syntax-check the middleware in the Open WebUI image."""
    path = Path("/app/backend/open_webui/utils/middleware.py")
    source = patch_middleware(path.read_text())
    compile(source, str(path), "exec")
    path.write_text(source)


if __name__ == "__main__":
    main()
