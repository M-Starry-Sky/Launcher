/// 拖放文件经识别后的归类。
enum DropImportKind {
  mod,
  resourcePack,
  shaderPack,
  world,
  skin,
  localPack,
  unknown,
}

extension DropImportKindLabel on DropImportKind {
  String get label => switch (this) {
        DropImportKind.mod => '模组',
        DropImportKind.resourcePack => '资源包',
        DropImportKind.shaderPack => '光影包',
        DropImportKind.world => '存档',
        DropImportKind.skin => '皮肤',
        DropImportKind.localPack => '整合包',
        DropImportKind.unknown => '未知',
      };

  String get folderHint => switch (this) {
        DropImportKind.mod => 'mods',
        DropImportKind.resourcePack => 'resourcepacks',
        DropImportKind.shaderPack => 'shaderpacks',
        DropImportKind.world => 'saves',
        DropImportKind.skin => 'skins',
        DropImportKind.localPack => 'local_packs',
        DropImportKind.unknown => '',
      };
}
