// projects.dart — Public-surface barrel for the projects feature: domain
// entities/repository interfaces plus presentation cubits/states/
// screens/widgets. The data layer (models, Drift*Repository
// implementations) is intentionally not exported — see
// flutter-conventions.md "Barrel files".

export 'domain/entities/baseline_asset.dart';
export 'domain/entities/baseline_manifest.dart';
export 'domain/entities/project.dart';
export 'domain/entities/project_override.dart';
export 'domain/entities/resolved_config_item.dart';
export 'domain/repositories/baseline_repository.dart';
export 'domain/repositories/project_repository.dart';
export 'presentation/cubit/active_project_cubit.dart';
export 'presentation/cubit/active_project_state.dart';
export 'presentation/cubit/create_project_cubit.dart';
export 'presentation/cubit/create_project_state.dart';
export 'presentation/cubit/project_hub_cubit.dart';
export 'presentation/cubit/project_hub_state.dart';
export 'presentation/screens/hub_screen.dart';
export 'presentation/screens/new_project_screen.dart';
export 'presentation/widgets/empty_hub_state.dart';
export 'presentation/widgets/project_card.dart';
export 'presentation/widgets/project_switcher_menu.dart';
