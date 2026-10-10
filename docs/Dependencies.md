# Зависимости и уведомления

| Компонент | Зафиксированная версия | Поставка | Лицензия / уведомления |
|---|---|---|---|
| Swift / SwiftUI / AppKit / WebKit | Сборка проверена Swift 6.4, Xcode 27.0 | macOS SDK; системные frameworks | Условия Xcode/Apple SDK; сторонние frameworks не копируются |
| PlantUML | 1.2025.0 | Неизменённый официальный Maven JAR, отдельный процесс | GPL-3.0-or-later; Runtime/PlantUML-LICENSE.txt, исходники Runtime/plantuml-1.2025.0-sources.jar |
| Eclipse Temurin JRE | 21.0.6+7, macOS aarch64 | Полный Runtime/jdk-21.0.6+7-jre | GPLv2 + Classpath/Assembly exceptions, дополнительные notices в Contents/Home/legal |
| Smetana | Версия из PlantUML 1.2025.0 | Уже включён в официальный JAR | Уведомления сохранены в исходниках и JAR |

CodeMirror, npm, отдельный Graphviz, облачные серверы и сторонние Swift packages не используются. Внутренние библиотеки PlantUML (включая ELK, JLaTeXMath, Guava и другие) остаются частью неизменённого официального JAR; вложенные META-INF license/POM сохранены, копии общих notices — Runtime/ThirdPartyNotices. Полный JRE поставляется вместе с его legal-каталогом.

Источники лицензий:

- https://plantuml.com/license
- https://adoptium.net/about/
- https://github.com/plantuml/plantuml/tree/v1.2025.0
- https://github.com/adoptium/temurin21-binaries/releases/tag/jdk-21.0.6%2B7

Приложение не опубликовано. Его собственная лицензия пользователем не определена. Для публичной поставки необходимо выбрать её и комплектовать соответствующие исходники и notices всех распространяемых компонентов; ad hoc подпись не заменяет Developer ID/notarization.

SHA-256 артефактов приведены в scripts/bootstrap-runtime.sh. Первичная загрузка требует сети, готовая сборка работает локально.
