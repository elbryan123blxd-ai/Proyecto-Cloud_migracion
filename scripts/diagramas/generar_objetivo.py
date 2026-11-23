"""Render the target PNG; update SVG/draw.io only when those files still exist."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import base64
import html
import math
import urllib.request
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / 'docs'
ASSETS = DOCS / 'diagram-assets'
ASSETS.mkdir(exist_ok=True)
BASE = 'https://raw.githubusercontent.com/awslabs/aws-icons-for-plantuml/main/dist/'
ICONS = {
    'client': 'General/Client.png',
    'cloudfront': 'NetworkingContentDelivery/CloudFront.png',
    'functions': 'NetworkingContentDelivery/CloudFrontFunctions.png',
    'alb': 'NetworkingContentDelivery/ElasticLoadBalancingApplicationLoadBalancer.png',
    'eni': 'NetworkingContentDelivery/VPCElasticNetworkInterface.png',
    'endpoint': 'NetworkingContentDelivery/VPCEndpoints.png',
    'igw': 'NetworkingContentDelivery/VPCInternetGateway.png',
    'fargate': 'Containers/Fargate.png',
    'task': 'Containers/ElasticContainerServiceTask.png',
    'ecr': 'Containers/ElasticContainerRegistry.png',
    'rds': 'Database/RDS.png',
    'dynamodb': 'Database/DynamoDB.png',
    'secrets': 'SecurityIdentityCompliance/SecretsManager.png',
    'iam': 'SecurityIdentityCompliance/IdentityandAccessManagement.png',
    'lambda': 'Compute/Lambda.png',
    'cloudwatch': 'ManagementGovernance/CloudWatch.png',
    's3': 'Storage/SimpleStorageService.png',
    'budget': 'CloudFinancialManagement/Budgets.png',
    'cost': 'CloudFinancialManagement/CostExplorer.png',
    'sns': 'ApplicationIntegration/SimpleNotificationService.png',
}


def fetch(item):
    name, remote = item
    path = ASSETS / (name + '.png')
    if not path.exists():
        request = urllib.request.Request(BASE + remote, headers={'User-Agent': 'project-architecture-diagram'})
        with urllib.request.urlopen(request, timeout=45) as response:
            data = response.read()
        path.write_bytes(data)
    with Image.open(path) as image:
        image.verify()


with ThreadPoolExecutor(max_workers=6) as pool:
    list(pool.map(fetch, ICONS.items()))

W, H, SCALE = 2000, 1580, 2
NAVY, GRAY = '#232F3E', '#64748B'
objects, flows = [], []


def group(id, x, y, w, h, title, color, fill, parent='1'):
    objects.append(dict(kind='group', id=id, x=x, y=y, w=w, h=h, title=title,
                        color=color, fill=fill, parent=parent))


def text(id, x, y, w, h, value, size=17, color=NAVY, parent='1', bold=False, align='center'):
    objects.append(dict(kind='text', id=id, x=x, y=y, w=w, h=h, title=value,
                        size=size, color=color, parent=parent, bold=bold, align=align))


def icon(id, name, cx, y, label, parent='1', size=64, subtitle=''):
    objects.append(dict(kind='icon', id=id, name=name, x=cx-size/2, y=y, w=size, h=size,
                        title='', parent=parent))
    text(id+'-label', cx-145, y+size+7, 290, 28, label, 18, parent=parent, bold=True)
    if subtitle:
        text(id+'-sub', cx-150, y+size+35, 300, 23, subtitle, 14, GRAY, parent)


def arrow(id, points, color='#475569', dashed=False, label='', label_at=None):
    flows.append(dict(id=id, points=points, color=color, dashed=dashed))
    if label:
        text(id+'-label', label_at[0]-145, label_at[1]-12, 290, 25, label, 15, color, bold=True)


text('title', 45, 25, 1600, 45, 'ACADEMIA PREMIER | Arquitectura objetivo', 33, bold=True, align='left')
text('subtitle', 45, 80, 1800, 30, 'Ohio · 2 AZ · 6 subredes · Un entorno por vista · 23 NOV 2026', 18, GRAY, align='left')
icon('browser', 'client', 185, 155, 'App Next.js', subtitle='Navegador activo')
icon('cf', 'cloudfront', 620, 150, 'CloudFront', subtitle='HTTPS · API sin caché', size=72)
icon('cf-functions', 'functions', 945, 155, 'Functions', subtitle='Rutas · CORS')
arrow('https', [(225, 190), (578, 190)], '#7C3AED', label='HTTPS :443', label_at=(400, 170))
arrow('functions-link', [(660, 190), (907, 190)], '#7C3AED', True)
for id, name, x, label in [('iam-global', 'iam', 1320, 'IAM / MFA'), ('budget-global', 'budget', 1500, 'Budget $120'),
                          ('sns-global', 'sns', 1680, 'SNS gastos'), ('cost-global', 'cost', 1860, 'Cost Explorer')]:
    icon(id, name, x, 150, label, size=56)
arrow('budget-email', [(1535, 180), (1645, 180)], '#DB2777')

group('region', 30, 310, 1940, 1035, 'AWS REGION · us-east-2 (Ohio)', '#00A4A6', '#FFFFFF')
group('vpc', 60, 360, 1400, 945, 'VPC · 10.0.0.0/16', '#8C4FFF', '#FCFAFF', 'region')
icon('igw', 'igw', 200, 395, 'Internet Gateway', 'vpc', 48)
icon('alb', 'alb', 750, 390, 'Un ALB', 'vpc', 64)
icon('s3-gateway', 'endpoint', 1250, 390, 'VPC endpoint S3', 'vpc', 48, 'Gateway · sin ENI')
arrow('cf-origin', [(620, 222), (620, 285), (750, 285), (750, 390)], '#7C3AED', label='Origen', label_at=(790, 330))
arrow('igw-association', [(230, 420), (705, 420)], GRAY, True)
text('public-route', 285, 425, 370, 28, 'RT pública → IGW', 15, GRAY, 'vpc')

for az, x, pub, app, data in [('a', 90, '10.0.0.0/24', '10.0.10.0/24', '10.0.20.0/24'),
                             ('b', 780, '10.0.1.0/24', '10.0.11.0/24', '10.0.21.0/24')]:
    suffix = az.upper()
    group('az-'+az, x, 495, 650, 780, 'AZ '+suffix, '#94A3B8', '#FFFFFF', 'vpc')
    group('pub-'+az, x+20, 545, 610, 160, 'Pública '+suffix+' · '+pub, '#7AA116', '#F3F8EB', 'az-'+az)
    icon('alb-eni-'+az, 'eni', x+325, 590, 'ENI del ALB', 'pub-'+az, 48)
    text('rt-app-'+az, x+60, 714, 480, 26, 'RT app '+suffix+' → S3 Gateway', 16, '#0369A1', 'az-'+az, True)
    arrow('rt-gateway-'+az, [(x+530, 726), (x+638, 726), (x+638, 480), (1250, 480), (1250, 438)], '#0369A1', True)
    group('app-'+az, x+20, 765, 610, 280, 'Privada app '+suffix+' · '+app, '#00A4A6', '#EDF9FA', 'az-'+az)
    icon('gotrue-'+az, 'fargate', x+155, 815, 'GoTrue', 'app-'+az, 56, ':9999 · SG-auth')
    icon('postgrest-'+az, 'fargate', x+455, 815, 'PostgREST', 'app-'+az, 56, ':3000 · SG-api')
    icon('endpoints-'+az, 'endpoint', x+230, 945, 'VPC endpoints Interface', 'app-'+az, 32)
    text('endpoint-services-'+az, x+40, 1007, 380, 35, 'ECR API · ECR DKR · Secrets · Logs', 13, GRAY, 'app-'+az)
    arrow('ecs-vpce-auth-'+az, [(x+155, 925), (x+155, 938), (x+230, 938), (x+230, 945)], '#0891B2')
    arrow('ecs-vpce-rest-'+az, [(x+455, 925), (x+455, 938), (x+230, 938)], '#0891B2')
    icon('aux-'+az, 'lambda' if az=='a' else 'task', x+510, 956,
         'Rotación' if az=='a' else 'Seed / SQL', 'app-'+az, 38)
    group('data-'+az, x+20, 1115, 610, 140, 'Privada datos '+suffix+' · '+data, '#C925D1', '#FCF3FD', 'az-'+az)
    icon('db-'+az, 'rds', x+300, 1155, 'Principal' if az=='a' else 'Standby', 'data-'+az, 54)
    arrow('alb-zone-'+az, [(720 if az=='a' else 780, 454), (720 if az=='a' else 780, 530),
                          (x+325, 530), (x+325, 590)], '#8C4FFF', True)
    arrow('alb-app-'+az, [(x+325, 638), (x+325, 750), (x+155, 750), (x+155, 815)], '#ED7100')
    arrow('alb-rest-'+az, [(x+325, 738), (x+455, 738), (x+455, 815)], '#ED7100')

text('endpoint-rds', 555, 1052, 470, 34, 'DNS de RDS · PostgreSQL TLS :5432', 18, '#A21CAF', 'vpc', True)
arrow('app-db-a', [(720, 850), (750, 850), (750, 1048), (650, 1048), (650, 1052)], '#A21CAF')
arrow('app-db-b', [(800, 850), (770, 850), (770, 1048), (930, 1048), (930, 1052)], '#A21CAF')
arrow('endpoint-writer', [(650, 1086), (650, 1100), (390, 1100), (390, 1155)], '#A21CAF')
arrow('replication', [(425, 1180), (1045, 1180)], '#A21CAF', label='Replicación síncrona', label_at=(750, 1158))

group('regional', 1490, 360, 450, 945, 'SERVICIOS REGIONALES', '#94A3B8', '#F8FAFC', 'region')
icon('ecr', 'ecr', 1605, 425, 'ECR', 'regional', subtitle='Imágenes')
icon('secrets', 'secrets', 1820, 425, 'Secrets Manager', 'regional', subtitle='Credenciales')
icon('cw', 'cloudwatch', 1605, 600, 'CloudWatch', 'regional', subtitle='Logs · métricas')
icon('s3', 's3', 1820, 600, 'S3', 'regional', subtitle='Archivos · artefactos')
text('vpce-note', 1510, 780, 410, 60, '4 endpoints Interface · 2 AZ\n8 ENI · SG-endpoints · HTTPS :443', 17, GRAY, 'regional')
text('s3-note', 1510, 855, 410, 50, 'S3 Gateway: asociado a RT app A / B\nDatos: rutas locales · Sin NAT', 17, GRAY, 'regional')
for az, x in [('a', 90), ('b', 780)]:
    lane = 740 if az == 'a' else 752
    arrow('vpce-services-'+az, [(x+247, 961), (x+325, 961), (x+325, lane), (1475, lane)], '#0891B2', True)
arrow('vpce-ecr', [(1475, 752), (1475, 405), (1605, 405), (1605, 425)], '#0891B2', True)
arrow('vpce-secrets', [(1475, 405), (1820, 405), (1820, 425)], '#0891B2', True)
arrow('vpce-logs', [(1475, 620), (1573, 620)], '#0891B2', True)
arrow('gateway-s3', [(1275, 414), (1438, 414), (1438, 580), (1820, 580), (1820, 600)], '#0369A1', True)
icon('tf-s3', 's3', 1605, 990, 'Estado S3', 'regional', 56)
icon('tf-lock', 'dynamodb', 1820, 990, 'Lock DynamoDB', 'regional', 56)
text('tf-note', 1510, 1110, 410, 55, 'Terraform\nEstados por entorno', 18, GRAY, 'regional')
text('rotation-note', 1510, 1200, 410, 55, 'Rotar → probar → renovar ECS', 17, '#B45309', 'regional')

group('env', 40, 1380, 850, 140, 'ENTORNOS SEPARADOS', '#64748B', '#F8FAFC')
text('env-names', 60, 1430, 810, 34, 'DEV   →   PREPROD (main)   →   PROD', 23, NAVY, 'env', True)
text('env-mode', 60, 1476, 810, 26, 'Dev: Single-AZ  |  Vista HA: Multi-AZ + tareas distribuidas', 16, GRAY, 'env')
group('notifs', 930, 1380, 1030, 140, 'NOTIFICACIONES EN LA APP', '#2563EB', '#EFF6FF')
text('notifs-flow', 950, 1430, 990, 34, 'App   ↔   PostgREST   ↔   PostgreSQL', 24, NAVY, 'notifs', True)
text('notifs-mode', 950, 1476, 990, 26, 'Polling mientras esté visible · RLS · Sin SNS / SQS / EventBridge', 17, GRAY, 'notifs')
text('footer', 45, 1535, 1910, 28, 'Objetivo, no inventario desplegado · Datos ficticios · Código actual: HTTP al origen; TLS pendiente · Pruebas por sesiones', 16, GRAY)

image = Image.new('RGB', (W*SCALE, H*SCALE), 'white')
draw = ImageDraw.Draw(image)
font_path = Path(r'C:\Windows\Fonts')
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">', '<rect width="100%" height="100%" fill="white"/>']
diagram = ET.Element('diagram', id='objetivo-6-subredes-2026-11-23', name='00 · Objetivo · 6 subredes y notificaciones')
model = ET.SubElement(diagram, 'mxGraphModel', page='1', pageWidth=str(W), pageHeight=str(H), grid='1', gridSize='10', background='#FFFFFF')
root = ET.SubElement(model, 'root')
ET.SubElement(root, 'mxCell', id='0')
ET.SubElement(root, 'mxCell', id='1', parent='0')
lookup = {o['id']:o for o in objects}


def cell(o, value, style):
    parent = lookup.get(o['parent'])
    c = ET.SubElement(root, 'mxCell', id=o['id'], value=value, style=style, vertex='1', parent=o['parent'])
    ET.SubElement(c, 'mxGeometry', x=str(o['x']-(parent['x'] if parent else 0)),
                  y=str(o['y']-(parent['y'] if parent else 0)), width=str(o['w']), height=str(o['h']), attrib={'as':'geometry'})


for o in objects:
    x,y,w,h = (o[k] for k in ('x','y','w','h'))
    if o['kind']=='group':
        draw.rectangle((x*SCALE,y*SCALE,(x+w)*SCALE,(y+h)*SCALE), fill=o['fill'], outline=o['color'], width=2*SCALE)
        svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{o["fill"]}" stroke="{o["color"]}" stroke-width="2"/>')
        f=ImageFont.truetype(str(font_path/'segoeuib.ttf'), 18*SCALE)
        draw.text(((x+14)*SCALE,(y+10)*SCALE), o['title'], font=f, fill=o['color'])
        svg.append(f'<text x="{x+14}" y="{y+28}" font-family="Segoe UI,Arial" font-size="18" font-weight="700" fill="{o["color"]}">{html.escape(o["title"])}</text>')
        cell(o, o['title'], f'container=1;collapsible=0;recursiveResize=0;html=1;align=left;verticalAlign=top;spacing=14;fontSize=18;fontStyle=1;strokeWidth=2;strokeColor={o["color"]};fontColor={o["color"]};fillColor={o["fill"]};')
    elif o['kind']=='icon':
        data=(ASSETS/(o['name']+'.png')).read_bytes()
        encoded=base64.b64encode(data).decode()
        icon_image=Image.open(ASSETS/(o['name']+'.png')).convert('RGBA').resize((int(w*SCALE),int(h*SCALE)),Image.Resampling.LANCZOS)
        image.paste(icon_image,(int(x*SCALE),int(y*SCALE)),icon_image)
        svg.append(f'<image x="{x}" y="{y}" width="{w}" height="{h}" href="data:image/png;base64,{encoded}"/>')
        cell(o, '', f'shape=image;aspect=fixed;imageAspect=0;image=data:image/png;base64,{encoded};')
    else:
        for i,line in enumerate(o['title'].split('\n')):
            f=ImageFont.truetype(str(font_path/('segoeuib.ttf' if o['bold'] else 'segoeui.ttf')),o['size']*SCALE)
            length=draw.textlength(line,font=f)/SCALE
            xx=x if o['align']=='left' else x+(w-length)/2
            yy=y+i*(o['size']+6)
            draw.text((xx*SCALE,yy*SCALE),line,font=f,fill=o['color'])
            svg.append(f'<text x="{xx}" y="{yy+o["size"]}" font-family="Segoe UI,Arial" font-size="{o["size"]}" font-weight="{700 if o["bold"] else 400}" fill="{o["color"]}">{html.escape(line)}</text>')
        cell(o, html.escape(o['title']).replace('\n','<br>'), f'text;html=1;whiteSpace=wrap;strokeColor=none;fillColor=none;align={o["align"]};verticalAlign=top;fontSize={o["size"]};fontColor={o["color"]};fontStyle={1 if o["bold"] else 0};')

for e in flows:
    points=e['points']; color=e['color']
    for a,b in zip(points,points[1:]):
        distance=math.dist(a,b)
        steps=range(0,int(distance),14) if e['dashed'] else [0]
        for start in steps:
            lo=start/distance; hi=min(start+8,distance)/distance if e['dashed'] else 1
            draw.line([(int((a[0]+(b[0]-a[0])*t)*SCALE),int((a[1]+(b[1]-a[1])*t)*SCALE)) for t in (lo,hi)],fill=color,width=2*SCALE)
    a,b=points[-2:]; angle=math.atan2(b[1]-a[1],b[0]-a[0])
    tip=[b,(b[0]-11*math.cos(angle-.45),b[1]-11*math.sin(angle-.45)),(b[0]-11*math.cos(angle+.45),b[1]-11*math.sin(angle+.45))]
    draw.polygon([(x*SCALE,y*SCALE) for x,y in tip],fill=color)
    svg.append(f'<polyline points="{" ".join(f"{x},{y}" for x,y in points)}" stroke="{color}" stroke-width="2" fill="none"'+(' stroke-dasharray="8 6"' if e['dashed'] else '')+'/>')
    svg.append(f'<polygon points="{" ".join(f"{x},{y}" for x,y in tip)}" fill="{color}"/>')
    c=ET.SubElement(root,'mxCell',id=e['id'],style=f'edgeStyle=none;endArrow=block;strokeWidth=2;strokeColor={color};dashed={1 if e["dashed"] else 0};',edge='1',parent='1')
    g=ET.SubElement(c,'mxGeometry',relative='1',attrib={'as':'geometry'})
    for point,role in [(points[0],'sourcePoint'),(points[-1],'targetPoint')]:
        ET.SubElement(g,'mxPoint',x=str(point[0]),y=str(point[1]),attrib={'as':role})
    if len(points)>2:
        array=ET.SubElement(g,'Array',attrib={'as':'points'})
        for x,y in points[1:-1]: ET.SubElement(array,'mxPoint',x=str(x),y=str(y))

svg.append('</svg>')
ids=[c.get('id') for c in root.findall('mxCell')]
assert len(ids)==len(set(ids))
assert all(f'{tier}-{az}' in ids for tier in ['pub','app','data'] for az in ['a','b'])
assert all(name in ids for name in ['s3-gateway', 'vpce-ecr', 'vpce-secrets', 'vpce-logs', 'gateway-s3'])
ET.fromstring('\n'.join(svg))
image.save(DOCS/'arquitectura-objetivo.png')
if (DOCS/'arquitectura-objetivo.svg').exists():
    (DOCS/'arquitectura-objetivo.svg').write_text('\n'.join(svg),encoding='utf-8')
path=DOCS/'arquitectura-seguridad.drawio'
if not path.exists():
    print('PNG actualizado. SVG/draw.io eliminados: no se regeneran.')
    raise SystemExit(0)
old=path.read_text(encoding='utf-8')
before=ET.fromstring(old)
start=old.index('<diagram id="objetivo-6-subredes-2026-11-23"')
end=old.index('</diagram>',start)+len('</diagram>')
updated=old[:start]+ET.tostring(diagram,encoding='unicode')+old[end:]
after=ET.fromstring(updated)
assert len(before.findall('diagram'))==len(after.findall('diagram'))
for page in before.findall('diagram'):
    if page.get('id')!=diagram.get('id'):
        assert ET.tostring(page)==ET.tostring(after.find(f"diagram[@id='{page.get('id')}']"))
ids=[c.get('id') for c in root.findall('mxCell')]
assert len(ids)==len(set(ids))
assert all(f'{tier}-{az}' in ids for tier in ['pub','app','data'] for az in ['a','b'])
ET.fromstring('\n'.join(svg))
path.write_text(updated,encoding='utf-8')
print('Diagrama con iconos AWS generado: PNG, SVG y primera pagina editable. Seis subredes verificadas.')
