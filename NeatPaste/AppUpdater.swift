import MacKitUpdater

/// 兼容旧调用点；实现见已发布 MacKit `SparkleUpdateChecker`（无自定义 Sparkle 用户驱动委托，可安全替换）。
typealias AppUpdater = SparkleUpdateChecker
