cl def:pub app -> JsxElement {
    has task_text: str = "";

    return
        <div>
            <input
                value={task_text}
                onChange="lambda e: any -> None { task_text = e.target.value; }"
            />
        </div>;
}
