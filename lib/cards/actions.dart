import '../config/dashboard.dart';
import 'env.dart';

/// What to call for a bare entity, by domain. Anything not listed toggles.
const domainService = {
  'script': ('script', 'turn_on'),
  'scene': ('scene', 'turn_on'),
  'automation': ('automation', 'trigger'),
  'button': ('button', 'press'),
  'input_button': ('input_button', 'press'),
  'vacuum': ('vacuum', 'start'),
};

/// An action the way a button states it: `service` (domain.service) with
/// optional `data`, else the service the entity's domain implies, else
/// homeassistant.toggle. The entity goes in as entity_id unless data names
/// one. The media card's favourites and tap use the same keys - same as
/// fireAction() in the web bundle.
void fireAction(PanelEnv env, {String? entity, String? service, Object? data}) {
  String domain, name;
  if (service != null && service.contains('.')) {
    final parts = service.split('.');
    domain = parts[0];
    name = parts[1];
  } else {
    final by = entity == null ? null : domainService[entity.split('.').first];
    domain = by?.$1 ?? 'homeassistant';
    name = by?.$2 ?? 'toggle';
  }
  final payload = <String, dynamic>{...?(data as Map?)?.cast<String, dynamic>()};
  if (entity != null && !payload.containsKey('entity_id')) payload['entity_id'] = entity;
  env.conn.callService(domain, name, payload);
}

/// The same, reading the keys off a config map (a button, a favourite).
void fireItem(PanelEnv env, CardConfig item) =>
    fireAction(env, entity: item.str('entity'), service: item.str('service'), data: item['data']);
