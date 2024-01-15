use bevy::prelude::*;

#[derive(Component)]
struct MyCamera;

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_systems(Startup, spawn_camera)
        .add_systems(Startup, spawn_cube)
        .add_systems(Update, move_camera)
        .run()
}

fn move_camera(
    keys: Res<Input<KeyCode>>,
    mut camera: Query<(&mut MyCamera, &mut Transform)>,
) {
    let (_, mut transform) = camera.get_single_mut().unwrap();

    if keys.pressed(KeyCode::W) {
        transform.translation.y += 1.;
    }
    if keys.pressed(KeyCode::S) {
        transform.translation.y -= 1.;
    }
    if keys.pressed(KeyCode::A) {
        transform.translation.x -= 1.;
    } 
    if keys.pressed(KeyCode::D) {
        transform.translation.x += 1.;
    }
}

fn spawn_camera(
    mut commands: Commands,
) {
    commands.spawn((
        Camera3dBundle {
            transform: Transform::from_xyz(10., 10., 10.)
                .looking_at(Vec3::ZERO, Vec3::Y),
                ..default()
        },
        MyCamera,
    ));
}

fn spawn_cube(
    mut commands: Commands,
    mut mesh: ResMut<Assets<Mesh>>,
) {

    let shape = mesh.add(shape::Cube::default().into());

    commands.spawn((
        PbrBundle {
            mesh: shape,
            transform: Transform::from_xyz(0., 0., 0.),
            ..default()
        },
    ));
}
