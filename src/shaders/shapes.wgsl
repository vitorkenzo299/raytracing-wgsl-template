fn hit_sphere(center: vec3f, radius: f32, r: ray, record: ptr<function, hit_record>, max: f32)
{
  record.hit_anything = false;

  // Substituindo o raio na equação da esfera, obtemos a*t² + b*t + c = 0.
  let oc = r.origin - center;
  let a = dot(r.direction, r.direction);
  let b = 2.0 * dot(oc, r.direction);
  let c = dot(oc, oc) - radius * radius;
  let delta = b * b - 4.0 * a * c;
  if (delta < 0.0)
  {
    return;
  }

  // Primeiro tentamos a interseção mais próxima; depois, a mais distante.
  let sqrt_delta = sqrt(delta);
  var t = (-b - sqrt_delta) / (2.0 * a);
  if (t < RAY_TMIN || t > max)
  {
    t = (-b + sqrt_delta) / (2.0 * a);
    if (t < RAY_TMIN || t > max)
    {
      return;
    }
  }

  record.t = t;
  record.p = ray_at(r, t);
  record.normal = (record.p - center) / radius;
  record.frontface = dot(r.direction, record.normal) < 0.0;
  if (!record.frontface)
  {
    record.normal = -record.normal;
  }
  record.hit_anything = true;
}

fn hit_quad(r: ray, Q: vec4f, u: vec4f, v: vec4f, record: ptr<function, hit_record>, max: f32)
{
  var n = cross(u.xyz, v.xyz);
  var normal = normalize(n);
  var D = dot(normal, Q.xyz);
  var w = n / dot(n.xyz, n.xyz);

  var denom = dot(normal, r.direction);
  if (abs(denom) < 0.0001)
  {
    record.hit_anything = false;
    return;
  }

  var t = (D - dot(normal, r.origin)) / denom;
  if (t < RAY_TMIN || t > max)
  {
    record.hit_anything = false;
    return;
  }

  var intersection = ray_at(r, t);
  var planar_hitpt_vector = intersection - Q.xyz;
  var alpha = dot(w, cross(planar_hitpt_vector, v.xyz));
  var beta = dot(w, cross(u.xyz, planar_hitpt_vector));

  if (alpha < 0.0 || alpha > 1.0 || beta < 0.0 || beta > 1.0)
  {
    record.hit_anything = false;
    return;
  }

  if (dot(normal, r.direction) > 0.0)
  {
    record.hit_anything = false;
    return;
  }

  record.t = t;
  record.p = intersection;
  record.normal = normal;
  record.hit_anything = true;
}

fn hit_triangle(r: ray, v0: vec3f, v1: vec3f, v2: vec3f, record: ptr<function, hit_record>, max: f32)
{
  var v1v0 = v1 - v0;
  var v2v0 = v2 - v0;
  var rov0 = r.origin - v0;

  var n = cross(v1v0, v2v0);
  var q = cross(rov0, r.direction);

  let denominator = dot(r.direction, n);
  if (abs(denominator) < 0.00000001)
  {
    record.hit_anything = false;
    return;
  }
  var d = 1.0 / denominator;

  var u = d * dot(-q, v2v0);
  var v = d * dot(q, v1v0);
  var t = d * dot(-n, rov0);

  if (u < 0.0 || u > 1.0 || v < 0.0 || (u + v) > 1.0)
  {
    record.hit_anything = false;
    return;
  }

  if (t < RAY_TMIN || t > max)
  {
    record.hit_anything = false;
    return;
  }

  record.t = t;
  record.p = ray_at(r, t);
  record.normal = normalize(n);
  record.hit_anything = true;
}

fn hit_box(r: ray, center: vec3f, rad: vec3f, record: ptr<function, hit_record>, t_max: f32)
{
  record.hit_anything = false;
  var near = -1e30;
  var far = 1e30;

  // Intersecta os intervalos de entrada e saída dos três eixos.
  for (var axis = 0; axis < 3; axis = axis + 1)
  {
    if (abs(r.direction[axis]) < 0.00000001)
    {
      if (r.origin[axis] < center[axis] - rad[axis] || r.origin[axis] > center[axis] + rad[axis])
      {
        return;
      }
    }
    else
    {
      let t1 = (center[axis] - rad[axis] - r.origin[axis]) / r.direction[axis];
      let t2 = (center[axis] + rad[axis] - r.origin[axis]) / r.direction[axis];
      near = max(near, min(t1, t2));
      far = min(far, max(t1, t2));
      if (near > far)
      {
        return;
      }
    }
  }

  var t = near;
  if (t < RAY_TMIN)
  {
    t = far;
  }
  if (t < RAY_TMIN || t > t_max)
  {
    return;
  }

  record.t = t;
  record.p = ray_at(r, t);
  let face = (record.p - center) / rad;
  let distance = abs(face);
  if (distance.x >= distance.y && distance.x >= distance.z)
  {
    record.normal = vec3f(sign(face.x), 0.0, 0.0);
  }
  else if (distance.y >= distance.z)
  {
    record.normal = vec3f(0.0, sign(face.y), 0.0);
  }
  else
  {
    record.normal = vec3f(0.0, 0.0, sign(face.z));
  }
  record.frontface = dot(r.direction, record.normal) < 0.0;
  if (!record.frontface)
  {
    record.normal = -record.normal;
  }
  record.hit_anything = true;
}

// Cilindro vertical finito: esta versão calcula apenas a lateral, sem tampas.
fn hit_cylinder(r: ray, center: vec3f, radius: f32, half_height: f32, record: ptr<function, hit_record>, t_max: f32)
{
  record.hit_anything = false;
  let oc = r.origin - center;
  let a = dot(r.direction.xz, r.direction.xz);
  if (a < 0.00000001 || radius <= 0.0 || half_height <= 0.0)
  {
    return;
  }

  let b = 2.0 * dot(oc.xz, r.direction.xz);
  let c = dot(oc.xz, oc.xz) - radius * radius;
  let delta = b * b - 4.0 * a * c;
  if (delta < 0.0)
  {
    return;
  }

  let sqrt_delta = sqrt(delta);
  var t = (-b - sqrt_delta) / (2.0 * a);
  for (var root = 0; root < 2; root = root + 1)
  {
    let point = ray_at(r, t);
    if (t >= RAY_TMIN && t <= t_max && abs(point.y - center.y) <= half_height)
    {
      record.t = t;
      record.p = point;
      record.normal = vec3f(point.x - center.x, 0.0, point.z - center.z) / radius;
      record.frontface = dot(r.direction, record.normal) < 0.0;
      if (!record.frontface)
      {
        record.normal = -record.normal;
      }
      record.hit_anything = true;
      return;
    }
    t = (-b + sqrt_delta) / (2.0 * a);
  }
}
