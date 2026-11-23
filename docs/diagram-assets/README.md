# Iconos del diagrama

Iconos AWS obtenidos del repositorio oficial de AWS Labs:
https://github.com/awslabs/aws-icons-for-plantuml/tree/main/dist

El mapeo de cada archivo a su URL de origen está en
`scripts/diagramas/generar_objetivo.py`. Consultar las condiciones de uso y licencia
del repositorio de origen. Los iconos se muestran conservando su proporción.

Para regenerar el PNG desde la raíz del proyecto:

```powershell
python scripts/diagramas/generar_objetivo.py
```

Requiere Python y Pillow. Descarga únicamente los iconos que falten; no accede a AWS.
Si existen SVG/draw.io previos, los actualiza; si fueron eliminados, no los recrea.
