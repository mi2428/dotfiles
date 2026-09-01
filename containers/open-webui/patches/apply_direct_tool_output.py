from pathlib import Path

path = Path("/app/backend/open_webui/utils/middleware.py")
source = path.read_text()


def replace_once(old: str, new: str) -> None:
    global source
    if source.count(old) != 1:
        raise RuntimeError(f"OpenWebUI middleware patch guard failed: {old[:80]!r}")
    source = source.replace(old, new)


replace_once(
    "from open_webui.models.notes import Notes",
    "from open_webui.models.notes import NoteForm, NoteUpdateForm, Notes\n"
    "from open_webui.utils.deep_research_notes import persist_deep_research_note",
)


replace_once(
    """                all_tool_call_sources = []  # Accumulated sources across all iterations
                user_message = get_last_user_message(form_data['messages'])
""",
    """                all_tool_call_sources = []  # Accumulated sources across all iterations
                direct_tool_output = None
                user_message = get_last_user_message(form_data['messages'])
""",
)
replace_once(
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
                        return_direct = bool(
                            tool_response_headers is not None
                            and str(tool_response_headers.get('X-OpenWebUI-Direct-Output', '')).casefold()
                            == 'true'
                            and str(tool_response_headers.get('Content-Type', '')).casefold().startswith('text/plain')
                        )
                        if tool_result is None:
""",
)
replace_once(
    """                                'content': tool_result_content(tool_result),
                                **({'files': tool_result_files} if tool_result_files else {}),
""",
    """                                'content': tool_result_content(tool_result),
                                'return_direct': return_direct,
                                **({'files': tool_result_files} if tool_result_files else {}),
""",
)
replace_once(
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
                        try:
                            await persist_deep_research_note(
                                notes=Notes,
                                note_form=NoteForm,
                                note_update_form=NoteUpdateForm,
                                user_id=user.id,
                                message_id=str(metadata.get('message_id') or ''),
                                chat_id=str(metadata.get('chat_id') or ''),
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
replace_once(
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

compile(source, str(path), "exec")
path.write_text(source)
