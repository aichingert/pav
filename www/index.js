const memory = new WebAssembly.Memory({
    initial: 10,
    maximum: 100,
});

const console_log = (ptr, len) => {
    const msg = new TextDecoder().decode(
        memory.buffer.slice(ptr, ptr + len),
    );
    console.log(msg);
};

window.onload = async () => {
    const wasm = await WebAssembly.instantiateStreaming(
        fetch("pav.wasm"), 
        {
            env: {
                memory,
                console_log,
            },
        },
    );
    const { memory, exports } = wasm.instance;
    console.log(exports);
    exports.add(1, 2);


    const name = new Uint8Array(memory.buffer);
    const { written: input_len } = new TextEncoder.encodeInto("hello.png", name);

    console.log(name.byteOffset);
    exports.parse_image(name.byteOffset, input_len, name.byteOffset);

    const upload_picture = document.getElementById("picture");

    upload_picture.addEventListener("change", (event) => {
        if (event.target.files.length <= 0) {
            return;
        }

        const reader = new FileReader();
        reader.onload = () => {
            console.log(reader.result);
        };
        reader.readAsArrayBuffer(event.target.files[0]);
    });

    const drop_area = document.getElementById("drop-area");
    drop_area.addEventListener("dragover", (event) => {
        event.stopPropagation();
        event.preventDefault();
        event.dataTransfer.dropEffect = "copy";
    });

    drop_area.addEventListener("drop", (event) => {
        event.stopPropagation();
        event.preventDefault();
        const fileList = event.dataTransfer.files;
        console.log(fileList);
    });

    drop_area.addEventListener("click", (event) => {
        upload_picture.click();
    });
}

