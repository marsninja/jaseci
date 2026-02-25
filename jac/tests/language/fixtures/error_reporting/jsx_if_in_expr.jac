cl def:pub app -> JsxElement {
    has loading: bool = True;

    return
        <div>
            {if loading { <span>Loading...</span> }}
            <h1>App</h1>
        </div>;
}
