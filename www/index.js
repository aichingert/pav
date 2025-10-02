var importObject = {
    env: {
        console_log: (arg) => console.log(arg),
    },
};

WebAssembly.instantiateStreaming(fetch("pav.wasm"), importObject).then((result) => {
    console.log(result.instance.exports);
    console.log(result.instance.exports.add(1, 2));

    const name = new Uint8Array([104, 101, 108, 108, 111, 46, 112, 110, 103]);

    console.log(result.instance.exports.parse_image(name.byteOffset, name.byteOffset));
});

window.onload = async () => {
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

