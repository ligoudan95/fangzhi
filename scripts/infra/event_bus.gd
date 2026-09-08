## doc: 07 §2 / 13 §3
## 事件总线（Autoload：Event）——Logic 层系统间解耦的唯一通道。
## 只发已提交事实；不承担请求、返回值、事务控制（铁律）。
## 信号随系统落地逐步增补，禁止一次性堆大而全。
extends Node

## 捕捉成功 → 图鉴/任务/成就各自监听（07 §2 示例）
signal on_capture_success(pet_id: int)

## 关卡通关 → 掉落结算/任务进度监听
signal on_stage_cleared(stage_id: int)

## 轻量通知（UI toast 等），payload 自描述
signal on_notify(kind: StringName, payload: Dictionary)
