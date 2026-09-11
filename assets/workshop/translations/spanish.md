# Survivor Leveling & Advancement [B42]

Gana puntos al subir tus habilidades y gástalos en las que tú elijas. SLA añade un nivel de superviviente y puntos de avance al panel habitual de habilidades, manteniendo la progresión natural. ¿Quieres que parte de ese progreso sobreviva a tu próxima mala decisión? La herencia de niveles opcional permite que tu siguiente personaje conserve un porcentaje de tu nivel de superviviente y reciba nuevos puntos para gastar.

Compatible con un jugador, multijugador, pantalla dividida y mando. Sin dependencias obligatorias.

## Cómo funciona el avance

La XP obtenida en habilidades compatibles también aumenta tu nivel de superviviente. Cada nivel te da un punto de avance, o AP. Gasta AP con los botones **+** junto a las habilidades. Por defecto, puedes ocupar tres espacios de avance a la vez. Practicar una habilidad mejorada libera sus espacios a medida que recuperas la XP que te saltaste. Esa XP también cuenta para el siguiente nivel de la habilidad.

El último avance hasta el máximo efectivo de una habilidad, normalmente del nivel 9 al 10, se considera dominarla. Cuesta 2 AP y requiere 2 espacios de avance libres. Después libera los espacios activos de esa habilidad. Si el límite Global o Por habilidad es 1, solo requiere 1 espacio libre, pero sigue costando 2 AP. El modo Libre no requiere espacios de avance y mantiene el coste de 2 AP. Una habilidad en su máximo efectivo no genera XP de superviviente adicional.

## Conserva parte del progreso tras morir

Activa la herencia del nivel de superviviente y elige cuánto pasa a tu siguiente personaje en el mismo mundo. Por ejemplo, morir con nivel de superviviente 20 y una herencia del 50% da a tu siguiente personaje nivel de superviviente 10 y 10 AP para gastar. Los niveles de tus antiguas habilidades no se copian, así que puedes elegir dónde gastar los puntos heredados. La herencia es opcional y está desactivada por defecto.

## Ajustes

- **Global:** Todas las habilidades comparten una reserva de espacios de avance configurable, con un límite predeterminado de 3 espacios activos en total.
- **Por habilidad:** Cada habilidad tiene su propio límite configurable, con un valor predeterminado para habilidades personalizadas compatibles y ajustes individuales opcionales para las habilidades originales.
- **Libre:** Elimina los límites de espacios de avance y las restricciones de recuperación de XP.
- Ajusta la velocidad de XP de superviviente sin cambiar la XP de las habilidades. Elige si contribuyen la forma física, la fuerza, cada habilidad original y las habilidades personalizadas compatibles.
- En las opciones de mods puedes activar marcadores de avance de mayor contraste o mostrar el porcentaje de XP de superviviente del jugador 1 en el reloj digital.
- Compatible con todos los idiomas estándar de los ajustes de idioma de Project Zomboid. Todas las traducciones se hicieron íntegramente con IA. Si ves algún texto incorrecto o confuso, avísame.

**Nota:** Cambiar de modo no reinicia el progreso registrado. La XP natural obtenida en modo Libre sigue reduciendo cualquier recuperación azul pendiente. Al volver a Global o Por habilidad, solo se restaura lo que queda pendiente.

## Añadir o quitar SLA

Puedes añadir o quitar SLA en partidas existentes. Las habilidades se conservan y el progreso anterior no concede niveles de superviviente retroactivos. Desactivar SLA oculta su interfaz, pero mantiene los niveles de habilidad obtenidos con AP. Al reactivarlo, restaura su estado y concilia la progresión compatible obtenida mientras estaba desactivado. Como con cualquier cambio de mods, recomiendo encarecidamente hacer una copia de seguridad de los mundos que quieras conservar.

## Servidores dedicados y partidas alojadas

Los administradores pueden otorgar XP de superviviente o niveles enteros a perfiles existentes, conectados o no. Los otorgamientos a perfiles desconectados se aplican inmediatamente. Borrar avances libera espacios sin devolver AP ni cambiar la XP de las habilidades. Para personajes desconectados queda pendiente y puede cancelarse hasta que vuelvan. Cambiar un nivel desde las estadísticas del jugador borra el registro de esa habilidad.

SLA usa el guardado normal de Project Zomboid. En servidores dedicados y partidas alojadas, activa SaveWorldEveryMinutes y cierra el servidor de forma normal.

## Compatibilidad

- **Incompatible: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Sin soporte actualmente: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) y [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. Estos mods sustituyen directamente reglas de progresión de las que depende SLA.
- **Depende del orden de carga: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Carga SLA después de Detailed Skill Tooltips para añadir el texto de recuperación azul de SLA a sus descripciones ampliadas. Si SLA carga primero, solo se sustituye ese texto. La progresión de superviviente y las descripciones de los botones + siguen funcionando.
- **Probados juntos: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939) y [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Esta combinación funcionó sin problemas en las pruebas, pero no se puede garantizar la compatibilidad con todos los mods de interfaz o habilidades personalizadas.
- Los mods que sustituyen la gestión de XP, los máximos o curvas de habilidad, el panel de habilidades, los menús de jugadores o el reloj digital pueden causar conflictos. SLA desactiva la integración afectada si se sustituyen sus enlaces necesarios. Las habilidades personalizadas necesitan una curva de XP utilizable y eventos de XP compatibles. Los cambios directos de habilidades o las rutas sin esos eventos no generan XP de superviviente.

## Uso de IA

Se usó IA para escribir todo el código de este proyecto. El concepto original, la dirección del diseño, las pruebas, la depuración y las decisiones de publicación son míos. He dedicado muchas horas a probar personalmente SLA y resolver problemas para que funcione como debe. Si prefieres no usar mods desarrollados con ayuda de IA, lo entiendo y respeto tu decisión.

## Apoyo

- Las donaciones en [Ko-fi](https://ko-fi.com/skeptic043) son opcionales. Ninguna función del mod requiere un pago.

## Información del mod

- Desarrollado/probado en la versión: 42.20.4
- Dependencias obligatorias: Ninguna
- Licencia: MIT
- [Código fuente e incidencias](https://github.com/Skeptic043/survivor-leveling-and-advancement)
