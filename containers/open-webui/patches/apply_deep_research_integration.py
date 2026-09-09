"""Apply guarded Deep Research backend and frontend changes to pinned Open WebUI."""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if source.count(old) != 1:
        raise RuntimeError(f"Open WebUI {label} patch guard failed: {old[:100]!r}")
    return source.replace(old, new)


MAIN_REPLACEMENTS = [
    (
        """from open_webui.utils.chat_variables import (
    normalize_chat_variables,
)
from open_webui.utils.embeddings import generate_embeddings
""",
        """from open_webui.utils.chat_variables import (
    normalize_chat_variables,
)
from open_webui.utils.deep_research_integration import (
    TRUST_KEY as DEEP_RESEARCH_TRUST_KEY,
    is_managed_deep_research_model,
    is_trusted_deep_research,
    persist_deep_research_intent,
    prepare_deep_research_request,
    request_deep_research_stop,
)
from open_webui.utils.embeddings import generate_embeddings
""",
    ),
    (
        """        model_info = None
        fallback_model = None
        missing_base_model = False
        if not model_item.get('direct', False):
""",
        """        model_info = None
        fallback_model = None
        missing_base_model = False
        managed_deep_research = False
        if model_item.get('direct', False):
            managed_deep_research = await is_managed_deep_research_model(
                model_id,
                None,
                registry_model=model_item,
                require_registry=True,
                direct=True,
            )
        if not model_item.get('direct', False):
""",
    ),
    (
        """            missing_base_model = bool(
                model_info and model_info.base_model_id and model_info.base_model_id not in request.app.state.MODELS
            )

            if missing_base_model and ENABLE_CUSTOM_MODEL_FALLBACK:
""",
        """            missing_base_model = bool(
                model_info and model_info.base_model_id and model_info.base_model_id not in request.app.state.MODELS
            )
            managed_deep_research = await is_managed_deep_research_model(
                model_id,
                model_info,
                registry_model=model,
                missing_base_model=missing_base_model,
                require_registry=True,
            )
            if managed_deep_research:
                tasks = None

            if missing_base_model and ENABLE_CUSTOM_MODEL_FALLBACK:
""",
    ),
    (
        """        if is_new_chat:
            metadata['chat_id'] = str(uuid4())

        initial_title_generation = None
""",
        """        if is_new_chat:
            metadata['chat_id'] = str(uuid4())

        if managed_deep_research:
            active_task_ids = (
                []
                if is_new_chat
                else await list_task_ids_by_item_id(request.app.state.redis, metadata['chat_id'])
            )
            form_data, metadata = await prepare_deep_research_request(
                form_data=form_data,
                metadata=metadata,
                user_id=user.id,
                message_ids=message_ids,
                is_new_chat=is_new_chat,
                active_task_ids=active_task_ids,
            )
            trusted_research = metadata[DEEP_RESEARCH_TRUST_KEY]
            if trusted_research['completed']:
                return {
                    'status': True,
                    'task_ids': [],
                    'chat_id': metadata['chat_id'],
                    'message_id': trusted_research['action_id'],
                    'completed': True,
                }
            if trusted_research['active_task_ids']:
                return {
                    'status': True,
                    'task_ids': trusted_research['active_task_ids'],
                    'chat_id': metadata['chat_id'],
                }

        initial_title_generation = None
""",
    ),
    (
        """        request.state.metadata = metadata
        form_data['metadata'] = metadata
""",
        """        if managed_deep_research:
            await persist_deep_research_intent(metadata)

        request.state.metadata = metadata
        form_data['metadata'] = metadata
""",
    ),
    (
        """                    and getattr(request.state, 'internal', False) is not True
                    and not await has_active_tasks(request.app.state.redis, chat_id)
""",
        """                    and getattr(request.state, 'internal', False) is not True
                    and not is_trusted_deep_research(metadata)
                    and not await has_active_tasks(request.app.state.redis, chat_id)
""",
    ),
    (
        """    result = await stop_item_tasks(request.app.state.redis, chat_id)

    if not socket_id and str(result.get('message', '')).startswith('No tasks found'):
""",
        """    deep_research_message_ids = []
    if not socket_id:
        deep_research_message_ids = await request_deep_research_stop(
            chat_id,
            user.id,
        )

    result = await stop_item_tasks(request.app.state.redis, chat_id)
    if deep_research_message_ids:
        result = {'status': True, 'message': 'Stopped Deep Research.'}
        for message_id in deep_research_message_ids:
            event_emitter = await get_event_emitter(
                {
                    'user_id': chat.user_id,
                    'chat_id': chat_id,
                    'message_id': message_id,
                },
                update_db=False,
            )
            if event_emitter:
                await event_emitter({'type': 'chat:completion', 'data': {'done': True}})
                await event_emitter({'type': 'chat:tasks:cancel'})

    if not socket_id and str(result.get('message', '')).startswith('No tasks found'):
""",
    ),
]


MIDDLEWARE_REPLACEMENTS = [
    (
        """from open_webui.utils.context_compaction import compact_messages_for_request
from open_webui.utils.files import (
""",
        """from open_webui.utils.context_compaction import compact_messages_for_request
from open_webui.utils.deep_research_integration import (
    is_trusted_deep_research,
    managed_pipe_payload,
)
from open_webui.utils.files import (
""",
    ),
    (
        """    if not isinstance(metadata.get('chat_id'), str):
        metadata['chat_id'] = ''

    # Pipeline Inlet -> Filter Inlet -> Chat Memory -> Chat Web Search -> Chat Image Generation
""",
        """    if not isinstance(metadata.get('chat_id'), str):
        metadata['chat_id'] = ''

    if is_trusted_deep_research(metadata):
        return managed_pipe_payload(form_data, metadata), metadata, []

    # Pipeline Inlet -> Filter Inlet -> Chat Memory -> Chat Web Search -> Chat Image Generation
""",
    ),
    (
        """    metadata = ctx['metadata']
    tasks = ctx['tasks']
    event_emitter = ctx['event_emitter']

    message = None
""",
        """    metadata = ctx['metadata']
    tasks = ctx['tasks']
    event_emitter = ctx['event_emitter']

    if is_trusted_deep_research(metadata):
        return

    message = None
""",
    ),
    (
        """    chat_id = metadata.get('chat_id', '')
    message_id = metadata.get('message_id')

    if not chat_id and not ctx.get('assistant_message'):
""",
        """    chat_id = metadata.get('chat_id', '')
    message_id = metadata.get('message_id')

    if is_trusted_deep_research(metadata):
        return

    if not chat_id and not ctx.get('assistant_message'):
""",
    ),
]


CHAT_REPLACEMENTS = [
    (
        """\tconst hasPendingAssistantLeaf = (messageId: string | null = null) =>
\t\t(messageId ? [history.messages[messageId]] : Object.values(history.messages)).some(
\t\t\t(message: any) =>
\t\t\t\tmessage?.role === 'assistant' && !message.done && (message.childrenIds?.length ?? 0) === 0
\t\t);
""",
        """\tconst DEEP_RESEARCH_MODEL_ID = 'sacloud.kimi-k2.7-deep-research';
\tconst DEEP_RESEARCH_MARKER = 'dotfiles:kimi-k2.7-deep-research';
\tlet deepResearchReattachInFlight: string | null = null;

\tconst hasPendingAssistantLeaf = (messageId: string | null = null) =>
\t\t(messageId ? [history.messages[messageId]] : Object.values(history.messages)).some(
\t\t\t(message: any) =>
\t\t\t\tmessage?.role === 'assistant' && !message.done && (message.childrenIds?.length ?? 0) === 0
\t\t);

\tconst getReattachableDeepResearchMessage = () =>
\t\tObject.values(history.messages).find(
\t\t\t(message: any) =>
\t\t\t\tmessage?.role === 'assistant' &&
\t\t\t\t(!message.done ||
\t\t\t\t\t!['delivered', 'needs_review', 'paused', 'failed', 'cancelled', 'cancel_requested'].includes(
\t\t\t\t\t\tmessage.meta?.deep_research?.state
\t\t\t\t\t)) &&
\t\t\t\t(message.childrenIds?.length ?? 0) === 0 &&
\t\t\t\tmessage.model === DEEP_RESEARCH_MODEL_ID &&
\t\t\t\tmessage.meta?.deep_research?.marker === DEEP_RESEARCH_MARKER &&
\t\t\t\tmessage.meta?.deep_research?.action_id === message.id &&
\t\t\t\ttypeof message.meta?.deep_research?.intent_signature === 'string'
\t\t);
""",
    ),
    (
        """\t\tif (!hasPendingAssistantLeaf()) {
\t\t\treturn;
\t\t}
""",
        """\t\tif (!hasPendingAssistantLeaf() && !getReattachableDeepResearchMessage()) {
\t\t\treturn;
\t\t}
""",
    ),
    (
        """\t\tif (pendingTaskIds?.length === 0) {
\t\t\tawait loadChat();
\t\t}
""",
        """\t\tif (pendingTaskIds?.length === 0) {
\t\t\tawait loadChat();
\t\t\tconst pendingMessage = getReattachableDeepResearchMessage();
\t\t\tif (pendingMessage) {
\t\t\t\tawait reattachDeepResearch(pendingMessage);
\t\t\t}
\t\t}
""",
    ),
    (
        """\t\t{
\t\t\tmessageIdsList,
\t\t\tregenerationPrompt,
\t\t\tcontinueResponse = false
\t\t}: {
\t\t\tmessageIdsList?: Array<{ model_id: string; message_id: string }>;
\t\t\tregenerationPrompt?: string | null;
\t\t\tcontinueResponse?: boolean;
\t\t} = {}
""",
        """\t\t{
\t\t\tmessageIdsList,
\t\t\tregenerationPrompt,
\t\t\tcontinueResponse = false,
\t\t\treattachResponse = false
\t\t}: {
\t\t\tmessageIdsList?: Array<{ model_id: string; message_id: string; modelIdx?: number }>;
\t\t\tregenerationPrompt?: string | null;
\t\t\tcontinueResponse?: boolean;
\t\t\treattachResponse?: boolean;
\t\t} = {}
""",
    ),
    (
        """\t\tconst responseMessage = _history.messages[responseMessageId];
\t\tconst userMessage = _history.messages[responseMessage.parentId];
""",
        """\t\tconst responseMessage = _history.messages[responseMessageId];
\t\tconst userMessage = _history.messages[responseMessage.parentId];
\t\tconst managedDeepResearch = model?.id === DEEP_RESEARCH_MODEL_ID;
""",
    ),
    (
        """\t\tif ($settings?.userLocation) {
\t\t\tuserLocation = await getAndUpdateUserLocation(localStorage.token).catch((err) => {
""",
        """\t\tif (!managedDeepResearch && $settings?.userLocation) {
\t\t\tuserLocation = await getAndUpdateUserLocation(localStorage.token).catch((err) => {
""",
    ),
    (
        """\t\tlet messages: any[] = [
\t\t\tparams?.system || $settings.system
\t\t\t\t? { role: 'system', content: `${params?.system ?? $settings?.system ?? ''}` }
\t\t\t\t: undefined
\t\t].filter(Boolean);
""",
        """\t\tlet messages: any[] = managedDeepResearch
\t\t\t? []
\t\t\t: [
\t\t\t\t\tparams?.system || $settings.system
\t\t\t\t\t\t? { role: 'system', content: `${params?.system ?? $settings?.system ?? ''}` }
\t\t\t\t\t\t: undefined
\t\t\t\t].filter(Boolean);
""",
    ),
    (
        """\t\t\t\tparams: {
\t\t\t\t\t...$settings?.params,
\t\t\t\t\t...params,
\t\t\t\t\tstop: getStopTokens()
\t\t\t\t},
""",
        """\t\t\t\tparams: managedDeepResearch
\t\t\t\t\t? {}
\t\t\t\t\t: {
\t\t\t\t\t\t\t...$settings?.params,
\t\t\t\t\t\t\t...params,
\t\t\t\t\t\t\tstop: getStopTokens()
\t\t\t\t\t\t},
""",
    ),
    (
        """\t\t\t\tfilter_ids: selectedFilterIds.length > 0 ? selectedFilterIds : undefined,
\t\t\t\ttool_ids: toolIds.length > 0 ? toolIds : undefined,
\t\t\t\tskill_ids: skillIds.length > 0 ? skillIds : undefined,
""",
        """\t\t\t\tfilter_ids:
\t\t\t\t\t!reattachResponse && selectedFilterIds.length > 0 ? selectedFilterIds : undefined,
\t\t\t\ttool_ids: !reattachResponse && toolIds.length > 0 ? toolIds : undefined,
\t\t\t\tskill_ids: !reattachResponse && skillIds.length > 0 ? skillIds : undefined,
""",
    ),
    (
        """\t\t\t\tterminal_id:
\t\t\t\t\tterminalEnabled &&
""",
        """\t\t\t\tterminal_id:
\t\t\t\t\t!reattachResponse &&
\t\t\t\t\tterminalEnabled &&
""",
    ),
    (
        """\t\t\t\ttool_servers: [
\t\t\t\t\t...($toolServers ?? []).filter(
\t\t\t\t\t\t(server, idx) => toolServerIds.includes(idx) || toolServerIds.includes(server?.id)
\t\t\t\t\t),
\t\t\t\t\t// Direct terminal servers — always included when enabled (not routed through selectedToolIds)
\t\t\t\t\t...($terminalServers ?? []).filter((t) => !t.id)
\t\t\t\t],
\t\t\t\tfeatures: getFeatures(),
\t\t\t\tvariables: {
\t\t\t\t\t...getPromptVariables(
\t\t\t\t\t\t$user?.name,
\t\t\t\t\t\t$settings?.userLocation ? userLocation : undefined,
\t\t\t\t\t\t$user?.email
\t\t\t\t\t)
\t\t\t\t},
""",
        """\t\t\t\ttool_servers: managedDeepResearch
\t\t\t\t\t? reattachResponse
\t\t\t\t\t\t? []
\t\t\t\t\t\t: ($toolServers ?? []).filter(
\t\t\t\t\t\t\t(server, idx) =>
\t\t\t\t\t\t\t\ttoolServerIds.includes(idx) || toolServerIds.includes(server?.id)
\t\t\t\t\t\t)
\t\t\t\t\t: [
\t\t\t\t\t\t\t...($toolServers ?? []).filter(
\t\t\t\t\t\t\t\t(server, idx) =>
\t\t\t\t\t\t\t\t\ttoolServerIds.includes(idx) || toolServerIds.includes(server?.id)
\t\t\t\t\t\t\t),
\t\t\t\t\t\t\t// Direct terminal servers — always included when enabled (not routed through selectedToolIds)
\t\t\t\t\t\t\t...($terminalServers ?? []).filter((t) => !t.id)
\t\t\t\t\t\t],
\t\t\t\tfeatures: reattachResponse ? {} : getFeatures(),
\t\t\t\tvariables: managedDeepResearch
\t\t\t\t\t? {}
\t\t\t\t\t: {
\t\t\t\t\t\t\t...getPromptVariables(
\t\t\t\t\t\t\t\t$user?.name,
\t\t\t\t\t\t\t\t$settings?.userLocation ? userLocation : undefined,
\t\t\t\t\t\t\t\t$user?.email
\t\t\t\t\t\t\t)
\t\t\t\t\t\t},
""",
    ),
    (
        """\t\t\t\t...(continueResponse ? { assistant_message_id: responseMessageId } : {}),
""",
        """\t\t\t\t...(continueResponse || reattachResponse
\t\t\t\t\t? { assistant_message_id: responseMessageId }
\t\t\t\t\t: {}),
""",
    ),
    (
        """\t\tawait tick();
\t\tif (shouldAutoScrollResponse()) {
\t\t\tscrollToBottom();
\t\t}
\t};

\tconst handleOpenAIError = async (error, responseMessage) => {
""",
        """\t\tawait tick();
\t\tif (shouldAutoScrollResponse()) {
\t\t\tscrollToBottom();
\t\t}
\t};

\tconst reattachDeepResearch = async (message: any) => {
\t\tif (deepResearchReattachInFlight || !$chatId) return;
\t\tconst model = $models.find((item) => item.id === DEEP_RESEARCH_MODEL_ID);
\t\tif (!model) return;

\t\tdeepResearchReattachInFlight = message.id;
\t\ttry {
\t\t\tawait sendMessageSocket(
\t\t\t\tmodel,
\t\t\t\tcreateMessagesList(history, message.id),
\t\t\t\tstructuredClone(history),
\t\t\t\tmessage.id,
\t\t\t\t$chatId,
\t\t\t\t{
\t\t\t\t\tmessageIdsList: [
\t\t\t\t\t\t{ model_id: model.id, message_id: message.id, modelIdx: message.modelIdx ?? 0 }
\t\t\t\t\t],
\t\t\t\t\treattachResponse: true
\t\t\t\t}
\t\t\t);
\t\t} finally {
\t\t\tdeepResearchReattachInFlight = null;
\t\t}
\t};

\tconst handleOpenAIError = async (error, responseMessage) => {
""",
    ),
    (
        """\t\t\tif ($chatId) {
\t\t\t\tawait stopTasksByChatId(localStorage.token, $chatId).catch((error) => {
\t\t\t\t\ttoast.error(`${error}`);
\t\t\t\t\treturn null;
\t\t\t\t});
\t\t\t} else {
""",
        """\t\t\tif ($chatId) {
\t\t\t\tconst stopped = await stopTasksByChatId(localStorage.token, $chatId).catch((error) => {
\t\t\t\t\ttoast.error(`${error}`);
\t\t\t\t\treturn null;
\t\t\t\t});
\t\t\t\tif (!stopped) return;
\t\t\t} else {
""",
    ),
]


def patch_source(source: str, replacements: list[tuple[str, str]], label: str) -> str:
    for old, new in replacements:
        source = replace_once(source, old, new, label)
    return source


def patch_tree(root: Path) -> None:
    targets = (
        (root / "backend/open_webui/main.py", MAIN_REPLACEMENTS, "main.py"),
        (
            root / "backend/open_webui/utils/middleware.py",
            MIDDLEWARE_REPLACEMENTS,
            "middleware.py",
        ),
        (
            root / "src/lib/components/chat/Chat.svelte",
            CHAT_REPLACEMENTS,
            "Chat.svelte",
        ),
    )
    patched_targets = []
    for path, replacements, label in targets:
        source = patch_source(path.read_text(), replacements, label)
        if path.suffix == ".py":
            compile(source, str(path), "exec")
        patched_targets.append((path, source))
    for path, source in patched_targets:
        path.write_text(source)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    patch_tree(args.root)


if __name__ == "__main__":
    main()
