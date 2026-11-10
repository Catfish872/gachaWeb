#!/usr/bin/env python3
"""Exercise production signer with a temporary test identity, never production secrets."""
import hashlib, os, pathlib, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='voidrift-signing-test-') as directory:
    root=pathlib.Path(directory); env=dict(os.environ,GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD='fixture-only',GODOT_ANDROID_KEYSTORE_RELEASE_USER='fixture',GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(root/'test.p12'))
    subprocess.run(['keytool','-genkeypair','-noprompt','-keystore',str(root/'test.p12'),'-storepass:env','GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD','-alias','fixture','-dname','CN=Isolated Content Test','-keyalg','RSA','-keysize','2048','-validity','1'],env=env,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    subprocess.run(['keytool','-exportcert','-keystore',str(root/'test.p12'),'-storepass:env','GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD','-alias','fixture','-file',str(root/'cert.der')],env=env,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    env['ANDROID_SIGNING_CERT_SHA256']=hashlib.sha256((root/'cert.der').read_bytes()).hexdigest()
    signer=['java',str(ROOT/'tools/build/SignContent.java')]
    subprocess.run(signer+['public',str(root/'public.pem')],env=env,check=True)
    (root/'manifest').write_bytes(b'{"schema":1}\n')
    subprocess.run(signer+['sign',str(root/'manifest'),str(root/'signature')],env=env,check=True)
    verify=['openssl','dgst','-sha256','-verify',str(root/'public.pem'),'-signature',str(root/'signature'),str(root/'manifest')]
    subprocess.run(verify,check=True,stdout=subprocess.DEVNULL)
    (root/'manifest').write_bytes(b'{"schema":2}\n')
    assert subprocess.run(verify,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0
    env['ANDROID_SIGNING_CERT_SHA256']='0'*64
    assert subprocess.run(signer+['public',str(root/'wrong.pem')],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0
    assert not (root/'wrong.pem').exists()
print('Content signing: existing-keystore extraction, signature verification, tamper rejection, certificate pin rejection PASS')
