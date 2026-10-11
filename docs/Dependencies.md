# Зависимости и уведомления

| Компонент | Зафиксированная версия | Поставка | Лицензия / уведомления |
|---|---|---|---|
| Swift / SwiftUI / AppKit / WebKit | Сборка проверена Swift 6.4, Xcode 27.0 | macOS SDK; системные frameworks | Условия Xcode/Apple SDK; сторонние frameworks не копируются |
| PlantUML | 1.2025.0 | Неизменённый официальный Maven JAR, отдельный процесс | GPL-3.0-or-later; Runtime/PlantUML-LICENSE.txt, исходники Runtime/plantuml-1.2025.0-sources.jar |
| Eclipse Temurin JRE | 21.0.6+7, macOS aarch64 | Полный Runtime/jdk-21.0.6+7-jre | GPLv2 + Classpath/Assembly exceptions, дополнительные notices в Contents/Home/legal |
| Smetana | Версия из PlantUML 1.2025.0 | Уже включён в официальный JAR | Уведомления сохранены в исходниках и JAR |
| Sparkle | 2.10.0 | Официальный binary Swift Package, framework внутри .app | MIT и вложенные notices; LICENSE скопирована в Resources/Sparkle-LICENSE.txt |

CodeMirror, npm и отдельный Graphviz не используются. Sparkle — единственный сторонний Swift Package; облачный хостинг применяется только для доставки обновлений. Внутренние библиотеки PlantUML (включая ELK, JLaTeXMath, Guava и другие) остаются частью неизменённого официального JAR; вложенные META-INF license/POM сохранены, копии общих notices — Runtime/ThirdPartyNotices. Полный JRE поставляется вместе с его legal-каталогом.

Источники лицензий:

- https://plantuml.com/license
- https://adoptium.net/about/
- https://github.com/plantuml/plantuml/tree/v1.2025.0
- https://github.com/adoptium/temurin21-binaries/releases/tag/jdk-21.0.6%2B7

Собственный код приложения распространяется по MIT, выбранной владельцем проекта. Лицензия MIT не изменяет лицензии сторонних компонентов. Их исходники и notices сохранены в Runtime; ad hoc подпись не заменяет Developer ID/notarization.

SHA-256 артефактов приведены в scripts/bootstrap-runtime.sh. Первичная загрузка требует сети, готовая сборка работает локально.
