// providers.dart — Public-surface barrel for the providers feature: domain
// enums/repository interfaces plus presentation cubits/states/screens/
// widgets. The data layer (SharedPrefsModelRoutingRepository) is
// intentionally not exported — see flutter-conventions.md "Barrel files".

export 'domain/enums/model_phase.dart';
export 'domain/enums/provider_connection_status.dart';
export 'domain/repositories/anthropic_api_key_repository.dart';
export 'domain/repositories/execution_context_cap_repository.dart';
export 'domain/repositories/model_routing_repository.dart';
export 'presentation/cubit/anthropic_provider_config_cubit.dart';
export 'presentation/cubit/anthropic_provider_config_state.dart';
export 'presentation/cubit/automation_settings_cubit.dart';
export 'presentation/cubit/automation_settings_state.dart';
export 'presentation/cubit/execution_context_cap_cubit.dart';
export 'presentation/cubit/execution_context_cap_state.dart';
export 'presentation/cubit/model_routing_cubit.dart';
export 'presentation/cubit/model_routing_state.dart';
export 'presentation/cubit/provider_settings_cubit.dart';
export 'presentation/cubit/provider_settings_state.dart';
export 'presentation/screens/settings_screen.dart';
export 'presentation/widgets/provider_connection_badge.dart';
