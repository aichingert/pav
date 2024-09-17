use winit::{
    event_loop::EventLoop,
    window::{Window, WindowAttributes},
};

async fn run(ev: EventLoop<()>, window: Window) {
    ev.run(move |_event, _target| {
    }).unwrap();
}

fn main() {
    let ev_loop = EventLoop::new().unwrap();
    let window = ev_loop.create_window(WindowAttributes::default()).unwrap();

    {
        pollster::block_on(run(ev_loop, window));
    }
}
