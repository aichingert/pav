use bevy::prelude::*;
use bevy::math::vec3;

#[derive(Component)]
struct MyCamera {
    x: f32,
    y: f32,

    vec: Vec3,
}

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_systems(Startup, spawn_camera)
        .add_systems(Startup, spawn_cube)
        .add_systems(Update, move_camera)
        .run();
}

fn move_camera(
    keys: Res<ButtonInput<KeyCode>>,
    mut camera: Query<(&mut MyCamera, &mut Transform)>,
) {
    let (mut values, mut transform) = camera.get_single_mut().unwrap();

    if keys.pressed(KeyCode::KeyW) {
        values.vec.x = 0.01;
        values.x += values.vec.x;
    }
    if keys.pressed(KeyCode::KeyS) {
        values.vec.x = -0.001;
    }
    if keys.pressed(KeyCode::KeyA) {
        values.vec.y = 0.001;
        values.y += values.vec.y;
    } 
    if keys.pressed(KeyCode::KeyD) {
        values.vec.y = -0.01;
        values.y += values.vec.y;
    }

    transform.rotate_around(Vec3::ZERO, Quat::from_rotation_x(values.x));
    transform.rotate_around(Vec3::ZERO, Quat::from_rotation_y(values.y));
}

fn spawn_camera(
    mut commands: Commands,
) { 
    commands.spawn((
        Camera3dBundle {
            transform: Transform::from_xyz(10., 10., 20.)
                .looking_at(Vec3::ZERO, Vec3::Y),
                ..default()
        },
        MyCamera { x: 0., y: 0., vec: vec3(0.0, 0.0, 0.0) },
    ));
}

fn spawn_cube(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
) {
    let shape = meshes.add(Cuboid::default());

    let data = std::fs::read_to_string("data").unwrap();

    for line in data.lines() {
        let (src, dst) = line.split_once("~").unwrap();

        let src_xyz = src.split(',').map(|s| s.parse::<i32>().unwrap()).collect::<Vec<_>>();
        let dst_xyz = dst.split(',').map(|s| s.parse::<i32>().unwrap()).collect::<Vec<_>>();

        for x in src_xyz[0]..=dst_xyz[0] {
            for y in src_xyz[1]..=dst_xyz[1] {
                for z in src_xyz[2]..=dst_xyz[2] {
                    commands.spawn((
                        PbrBundle {
                            mesh: shape.clone(),
                            transform: Transform::from_xyz(x as f32, z as f32, y as f32),
                            ..default()
                        },
                    ));
                }
            }
        }
    }
}
