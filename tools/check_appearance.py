"""Spatial/temporal/causal-feature acceptance of production-worker images.
No primary-geometry correspondence is used for refracted internal features.
"""
import argparse, hashlib, json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/appearance-corpus'
def decode(v):return np.where(v<=.04045,v/12.92,((v+.055)/1.055)**2.4)
def encode(v):return np.where(v<=.0031308,12.92*v,1.055*np.maximum(v,0)**(1/2.4)-.055)
def composite(image,bg):return encode(decode(image[...,:3])*image[...,3:]+np.array(bg)*(1-image[...,3:]))*255
def rms(v):return float(np.sqrt(np.mean(np.square(v))))
def signals(reference,candidate,mask):
    error=(candidate-reference)[:,mask,:]
    rd=np.roll(reference,-1,axis=0)-reference
    cd=np.roll(candidate,-1,axis=0)-candidate
    r=rd[:,mask,:];c=cd[:,mask,:]
    return {'spatial_rmse_lsb':rms(error),'mean_bias_lsb':float(np.max(np.abs(np.mean(error,axis=(0,1))))),
        'temporal_residual_lsb':rms(c-r),'reference_motion_lsb':rms(r),
        'motion_gain':float(np.sum(r*c)/max(np.sum(r*r),1e-12)),
        'loop_seam_residual_lsb':rms((cd[-1]-rd[-1])[mask])}
def feature_metrics(reference,candidate,control,mask):
    signal=(reference-control)[:,mask,:];actual=(candidate-control)[:,mask,:]
    power=np.sum(signal*signal)
    return {'pixels':int(mask.sum()),'reference_signal_lsb':rms(signal),
        'gain':float(np.sum(signal*actual)/max(power,1e-12)),
        'relative_residual':float(np.sqrt(np.sum((actual-signal)**2)/max(power,1e-12))),
        'correlation':float(np.sum(signal*actual)/max(np.sqrt(power*np.sum(actual*actual)),1e-12))}
def main():
    args=argparse.ArgumentParser();args.add_argument('--inspect',action='store_true');opt=args.parse_args()
    config=json.loads((ROOT/'data/lapidary/acceptance/corpus.json').read_text())
    report=json.loads((OUT/'report.json').read_text());records=report['records'];missing=[];results=[];failures=[]
    threshold_path=ROOT/'data/lapidary/acceptance/thresholds.json'
    thresholds=json.loads(threshold_path.read_text()) if threshold_path.exists() else None
    def get(case,rig,size,frame,profile,stream):
        key=f'{case}-{rig}-{size}-{frame}-{profile}-{stream}'
        path=OUT/'images'/f'{key}.png'
        if key not in records or not path.exists():missing.append(key);return None
        assert hashlib.sha256(path.read_bytes()).hexdigest()==records[key]['png_sha256'],f'Corrupt image {key}'
        job_path=OUT/'jobs'/f'{key}.res'
        assert job_path.exists() and hashlib.sha256(job_path.read_bytes()).hexdigest()==records[key].get('request_sha256'),f'Corrupt frozen request {key}'
        im=np.array(Image.open(path).convert('RGBA'),dtype=np.float64)/255
        assert im.shape==(size,size,4),key
        return im
    for case in config['cases']:
      for rig in config['rigs']:
       for size in config['sizes']:
        ref_images=[get(case,rig,size,f,'reference',0) for f in range(config['frames'])]
        ref1=get(case,rig,size,0,'reference',1)
        if any(x is None for x in ref_images) or ref1 is None:continue
        ref_images=np.array(ref_images);mask=np.max(ref_images[...,3],axis=0)>.01
        control_images=None
        if case in config['feature_controls']:
            control_images=[get(config['feature_controls'][case],rig,size,f,'reference',0) for f in range(config['frames'])]
            if any(x is None for x in control_images):continue
            control_images=np.array(control_images)
        for profile in ['draft','detail']:
         for stream in [0,1]:
          images=[get(case,rig,size,f,profile,stream) for f in range(config['frames'])]
          if any(x is None for x in images):continue
          images=np.array(images)
          item={'case':case,'rig':rig,'size':size,'profile':profile,'stream':stream,'backgrounds':{}}
          times=[records[f'{case}-{rig}-{size}-{f}-{profile}-{stream}']['wall_ms'] for f in range(config['frames'])]
          item['frame_wall_ms']={'median':float(np.median(times)),'p95':float(np.percentile(times,95)),'max':max(times)}
          for name,bg in config['backgrounds'].items():
            ref=composite(ref_images,bg);cand=composite(images,bg)
            metrics=signals(ref,cand,mask)
            metrics['reference_noise_lsb']=rms((ref[0]-composite(ref1,bg))[mask])/np.sqrt(2)
            if control_images is not None:
                control=composite(control_images,bg)
                # Causal optical difference defines features at each pose. Noise
                # cannot manufacture the ROI: require >6 reference noise and 8 LSB.
                strength=np.sqrt(np.mean((ref-control)**2,axis=(0,3)))
                feature_mask=mask&(strength>max(8,6*metrics['reference_noise_lsb']))
                metrics['feature']=feature_metrics(ref,cand,control,feature_mask) if feature_mask.any() else {'pixels':0}
            item['backgrounds'][name]=metrics
          results.append(item)
          if thresholds and thresholds['selected_profiles'].get(case)==profile:
            limits=thresholds['limits'][case]
            for bg,m in item['backgrounds'].items():
              for metric,limit in limits.items():
                if metric in m and m[metric]>limit:failures.append(f'{case}/{rig}/{size}/{stream}/{bg} {metric}={m[metric]:.4f} > {limit}')
              if m['reference_motion_lsb']>2 and not .9<=m['motion_gain']<=1.1:failures.append(f'{case}/{rig}/{size}: real motion gain {m["motion_gain"]}')
              if 'feature' in m:
                f=m['feature']
                if f['pixels']<4 or not .85<=f.get('gain',0)<=1.15 or f.get('correlation',0)<.9 or f.get('relative_residual',1)>.35:failures.append(f'{case}/{rig}/{size}: feature {f}')
    if not thresholds:failures.append('Reference review and explicit selected profile thresholds are missing')
    result={'status':'incomplete' if missing else ('failed' if failures else 'passed'),'missing_count':len(missing),'failures':failures,'results':results,'config_sha256':hashlib.sha256((ROOT/'data/lapidary/acceptance/corpus.json').read_bytes()).hexdigest()}
    (OUT/'analysis.json').write_text(json.dumps(result,indent=2))
    print(json.dumps({'status':result['status'],'complete_comparisons':len(results),'missing':len(missing),'failures':failures[:30]}))
    for case in config['cases']:
      for profile in ['draft','detail']:
        subset=[m for r in results if r['case']==case and r['profile']==profile for m in r['backgrounds'].values()]
        if subset:print(case,profile,json.dumps({key:max(m[key] for m in subset) for key in ['spatial_rmse_lsb','mean_bias_lsb','temporal_residual_lsb','reference_noise_lsb']}))
    print('CHECK_COMPLETE: check_appearance')
    return 0 if opt.inspect or result['status']=='passed' else 1
if __name__=='__main__':raise SystemExit(main())
