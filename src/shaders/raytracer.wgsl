const THREAD_COUNT = 16;
const RAY_TMIN = 0.0001;
const RAY_TMAX = 100.0;
const PI = 3.1415927f;
const FRAC_1_PI = 0.31830987f;
const FRAC_2_PI = 1.5707964f;

@group(0) @binding(0)  
  var<storage, read_write> fb : array<vec4f>;

@group(0) @binding(1)
  var<storage, read_write> rtfb : array<vec4f>;

@group(1) @binding(0)
  var<storage, read_write> uniforms : array<f32>;

@group(2) @binding(0)
  var<storage, read_write> spheresb : array<sphere>;

@group(2) @binding(1)
  var<storage, read_write> quadsb : array<quad>;

@group(2) @binding(2)
  var<storage, read_write> boxesb : array<box>;

@group(2) @binding(3)
  var<storage, read_write> trianglesb : array<triangle>;

@group(2) @binding(4)
  var<storage, read_write> meshb : array<mesh>;

struct ray {
  origin : vec3f,
  direction : vec3f,
};

struct sphere {
  transform : vec4f,
  color : vec4f,
  material : vec4f,
};

struct quad {
  Q : vec4f,
  u : vec4f,
  v : vec4f,
  color : vec4f,
  material : vec4f,
};

struct box {
  center : vec4f,
  radius : vec4f,
  rotation: vec4f,
  color : vec4f,
  material : vec4f,
};

struct triangle {
  v0 : vec4f,
  v1 : vec4f,
  v2 : vec4f,
};

struct mesh {
  transform : vec4f,
  scale : vec4f,
  rotation : vec4f,
  color : vec4f,
  material : vec4f,
  min : vec4f,
  max : vec4f,
  show_bb : f32,
  start : f32,
  end : f32,
};

struct material_behaviour {
  scatter : bool,
  direction : vec3f,
};

struct camera {
  origin : vec3f,
  lower_left_corner : vec3f,
  horizontal : vec3f,
  vertical : vec3f,
  u : vec3f,
  v : vec3f,
  w : vec3f,
  lens_radius : f32,
};

struct hit_record {
  t : f32,
  p : vec3f,
  normal : vec3f,
  object_color : vec4f,
  object_material : vec4f,
  frontface : bool,
  hit_anything : bool,
};

fn ray_at(r: ray, t: f32) -> vec3f
{
  return r.origin + t * r.direction;
}

fn get_ray(cam: camera, uv: vec2f, rng_state: ptr<function, u32>) -> ray
{
  var rd = cam.lens_radius * rng_next_vec3_in_unit_disk(rng_state);
  var offset = cam.u * rd.x + cam.v * rd.y;
  return ray(cam.origin + offset, normalize(cam.lower_left_corner + uv.x * cam.horizontal + uv.y * cam.vertical - cam.origin - offset));
}

fn get_camera(lookfrom: vec3f, lookat: vec3f, vup: vec3f, vfov: f32, aspect_ratio: f32, aperture: f32, focus_dist: f32) -> camera
{
  var camera = camera();
  camera.lens_radius = aperture / 2.0;

  var theta = degrees_to_radians(vfov);
  var h = tan(theta / 2.0);
  var w = aspect_ratio * h;

  camera.origin = lookfrom;
  camera.w = normalize(lookfrom - lookat);
  camera.u = normalize(cross(vup, camera.w));
  camera.v = cross(camera.u, camera.w);

  camera.lower_left_corner = camera.origin - w * focus_dist * camera.u - h * focus_dist * camera.v - focus_dist * camera.w;
  camera.horizontal = 2.0 * w * focus_dist * camera.u;
  camera.vertical = 2.0 * h * focus_dist * camera.v;

  return camera;
}

fn envoriment_color(direction: vec3f, color1: vec3f, color2: vec3f) -> vec3f
{
  var unit_direction = normalize(direction);
  var t = 0.5 * (unit_direction.y + 1.0);
  var col = (1.0 - t) * color1 + t * color2;

  var sun_direction = normalize(vec3(uniforms[13], uniforms[14], uniforms[15]));
  var sun_color = int_to_rgb(i32(uniforms[17]));
  var sun_intensity = uniforms[16];
  var sun_size = uniforms[18];

  var sun = clamp(dot(sun_direction, unit_direction), 0.0, 1.0);
  col += sun_color * max(0, (pow(sun, sun_size) * sun_intensity));

  return col;
}

fn check_ray_collision(r: ray, max: f32) -> hit_record
{
  var spheresCount = i32(uniforms[19]);
  var closest = hit_record();
  closest.t = max;
  var record = hit_record();

  // Cada teste só aceita colisões mais próximas que a melhor encontrada.
  for (var i = 0; i < spheresCount; i = i + 1)
  {
    let object = spheresb[i];
    hit_sphere(object.transform.xyz, object.transform.w, r, &record, closest.t);
    if (record.hit_anything)
    {
      record.object_color = object.color;
      record.object_material = object.material;
      closest = record;
    }
  }

  return closest;
}

fn lambertian(normal : vec3f, absorption: f32, random_sphere: vec3f, rng_state: ptr<function, u32>) -> material_behaviour
{
  // A absorção pode encerrar o raio antes de ele ser espalhado.
  if (absorption >= 1.0)
  {
    return material_behaviour(false, normal);
  }
  if (rng_next_float(rng_state) < clamp(absorption, 0.0, 1.0))
  {
    return material_behaviour(false, normal);
  }

  var direction = normal + random_sphere;
  if (dot(direction, direction) < 0.00000001)
  {
    direction = normal;
  }

  return material_behaviour(true, normalize(direction));
}

fn metal(normal : vec3f, direction: vec3f, fuzz: f32, random_sphere: vec3f) -> material_behaviour
{
  let reflected = reflect(normalize(direction), normal);
  // O fuzz desvia o reflexo perfeito para deixá-lo borrado.
  let scattered = reflected + clamp(fuzz, 0.0, 1.0) * random_sphere;
  if (dot(scattered, normal) <= 0.0)
  {
    return material_behaviour(false, normal);
  }
  return material_behaviour(true, normalize(scattered));
}

fn dielectric(normal : vec3f, r_direction: vec3f, refraction_index: f32, frontface: bool, random_sphere: vec3f, fuzz: f32, rng_state: ptr<function, u32>) -> material_behaviour
{  
  return material_behaviour(false, vec3f(0.0));
}

fn emmisive(color: vec3f, light: f32) -> material_behaviour
{
  return material_behaviour(false, vec3f(0.0));
}

fn trace(r: ray, rng_state: ptr<function, u32>) -> vec3f
{
  let maxbounces = i32(uniforms[2]);
  var color = vec3f(1.0);
  var current_ray = r;

  let backgroundcolor1 = int_to_rgb(i32(uniforms[11]));
  let backgroundcolor2 = int_to_rgb(i32(uniforms[12]));

  for (var bounce = 0; bounce < maxbounces; bounce = bounce + 1)
  {
    let record = check_ray_collision(current_ray, RAY_TMAX);
    if (!record.hit_anything)
    {
      return color * envoriment_color(current_ray.direction, backgroundcolor1, backgroundcolor2);
    }

    let albedo = record.object_color.xyz;
    let material = record.object_material;
    if (material.x < 0.0)
    {
      return vec3f(0.0);
    }

    let random_sphere = rng_next_vec3_in_unit_sphere(rng_state);
    let smoothness = clamp(material.x, 0.0, 1.0);
    var behaviour = material_behaviour();

    if (rng_next_float(rng_state) < smoothness)
    {
      behaviour = metal(record.normal, current_ray.direction, material.y, random_sphere);
    }
    else
    {
      behaviour = lambertian(record.normal, material.y, random_sphere, rng_state);
    }
    color *= albedo;

    if (!behaviour.scatter)
    {
      return vec3f(0.0);
    }

    if (dot(behaviour.direction, behaviour.direction) < 0.00000001)
    {
      behaviour.direction = record.normal;
    }
    current_ray = ray(record.p, normalize(behaviour.direction));
  }

  return vec3f(0.0);
}

@compute @workgroup_size(THREAD_COUNT, THREAD_COUNT, 1)
fn render(@builtin(global_invocation_id) id : vec3u)
{
    var rez = uniforms[1];
    var time = u32(uniforms[0]);
    if (id.x >= u32(rez) || id.y >= u32(rez))
    {
      return;
    }

    // Cada pixel tem sua própria sequência de números aleatórios.
    var rng_state = init_rng(vec2(id.x, id.y), vec2(u32(rez)), time);

    var fragCoord = vec2f(f32(id.x), f32(id.y));

    var lookfrom = vec3(uniforms[7], uniforms[8], uniforms[9]);
    var lookat = vec3(uniforms[23], uniforms[24], uniforms[25]);

    var cam = get_camera(lookfrom, lookat, vec3(0.0, 1.0, 0.0), uniforms[10], 1.0, uniforms[6], uniforms[5]);
    var samples_per_pixel = max(1, i32(uniforms[4]));

    var color = vec3f(0.0);

    // Dispara várias amostras para o pixel e calcula a média das cores.
    for (var i = 0; i < samples_per_pixel; i = i + 1)
    {
      let uv = (fragCoord + sample_square(&rng_state)) / vec2f(rez);
      let r = get_ray(cam, uv, &rng_state);
      color += trace(r, &rng_state);
    }
    color /= f32(samples_per_pixel);

    let pixel_index = mapfb(id.xy, rez);
    let should_accumulate = uniforms[3] > 0.0;

    // xyz guarda a soma das cores; w conta quantos frames foram somados.
    var accumulated = vec4f(color, 1.0);
    if (should_accumulate)
    {
      accumulated += rtfb[pixel_index];
    }
    rtfb[pixel_index] = accumulated;

    let average = accumulated.xyz / accumulated.w;
    fb[pixel_index] = vec4f(linear_to_gamma(max(average, vec3f(0.0))), 1.0);
}
