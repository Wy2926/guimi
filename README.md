# 烬庭 · Ember Yard

Godot 4.7 的 2.5D 竞技场肉鸽原型。双击 `Play.cmd` 启动，或用 Godot 导入 `project.godot`。

## 架构

`arena.gd` 组装对局并管理暂停、胜负与重开；玩家、敌人、成长、刷怪、技能和界面各自负责本域逻辑，通过显式依赖与信号协作。属性和技能数值使用原生 Resource，伤害统一由 `damage_rules.gd` 计算，表现复用场景、动画、粒子与着色器。

## 目录职责

| 目录 | 职责 |
| --- | --- |
| `scenes/` | 主场景、角色与可复用场景 |
| `scripts/` | 对局、战斗、成长、技能、表现与界面逻辑，以及启动脚本 |
| `data/` | 职业属性与技能配置 |
| `assets/` | 模型、材质、音频、字体；自制资源包含概念图和 Blender 源文件 |
| `shaders/` | 共用着色器；资源专用着色器随对应资产存放 |
| `tools/` | 现有自动验证与模型制作工具 |
| `docs/` | [玩法数值与架构细节](docs/gameplay-architecture.md) |
| `licenses/` | 第三方素材许可，来源见 [THIRD_PARTY.md](THIRD_PARTY.md) |

## 验证

运行 `./scripts/run.ps1 -Verify`。默认无窗口，报告写入忽略目录 `artifacts/`；只验证逻辑、资源和生命周期，不代表画面、音频或 GPU 性能验收。
