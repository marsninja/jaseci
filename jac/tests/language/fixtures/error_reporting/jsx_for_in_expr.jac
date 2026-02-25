cl def:pub app -> JsxElement {
    has tasks: list = [];

    return
        <div>
            { for t in tasks { <div>{t.title}</div> } }
        </div>;
}
