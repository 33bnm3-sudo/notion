# -*- coding: utf-8 -*-
"""STL -> STEP 변환 핵심 로직.

stl2step.bat 이 FreeCAD 콘솔(freecadcmd)로 이 파일을 실행한다.
입력/출력 경로는 환경변수 STL2STEP_IN / STL2STEP_OUT 으로 받는다.

동작 순서
  1. STL 읽기 + 간단한 메쉬 정리 (중복 점/면 제거, 면 방향 통일)
  2. 같은 평면에 놓인 이웃 삼각형들을 한 덩어리(영역)로 묶기
  3. 각 영역의 점들을 평면 위로 정확히 맞추고, 영역 테두리 선 구하기
     (두 평면이 만나는 직선 위의 쓸데없는 중간 점은 제거)
  4. 영역마다 면 하나씩 만들기 - 면끼리 모서리를 공유하게 만들어서 꿰매기(sewing) 불필요
  5. 셸 -> 솔리드로 만들고 원본 메쉬와 부피 비교
  6. 문제가 있으면 FreeCAD 기본 방식(삼각형 = 면)으로 자동 전환 후 STEP 저장
"""
import os
import sys
import math
import time
import traceback

# ---- 조절 가능한 값 -------------------------------------------------------
ANGLE_TOL_DEG = 1.0    # 이웃 삼각형 기울기 차이가 이 각도 이하이면 같은 평면 후보
DIST_TOL_REL = 2e-6    # 평면에서 벗어난 거리 허용치 (모델 대각선 길이 대비 비율)
VOLUME_TOL = 0.005     # 결과 부피가 원본 메쉬와 0.5% 넘게 다르면 기본 방식으로 전환
# --------------------------------------------------------------------------


class Progress:
    """콘솔에 진행 막대를 그린다. stdout 은 로그 파일로 돌려져 있으므로 콘솔에 직접 쓴다."""

    def __init__(self):
        self.out = None
        if os.name == "nt":
            try:
                self.out = open("CONOUT$", "wb", buffering=0)
            except Exception:
                self.out = None
        self.last = 0.0
        self.start = time.time()
        self.lo, self.hi = 0.0, 1.0   # 현재 구간 (전체 진행률 중 이 단계가 차지하는 범위)
        self.label = ""

    def _write(self, text):
        data = text.encode("utf-8")
        try:
            if self.out:
                self.out.write(data)
            else:
                os.write(2, data)
        except Exception:
            pass

    def stage(self, lo, hi, label):
        self.lo, self.hi, self.label = lo, hi, label
        log("[%5.1fs] %s" % (time.time() - self.start, label))
        self.update(0.0, force=True)

    def update(self, frac, force=False, detail=""):
        now = time.time()
        if not force and now - self.last < 0.2:
            return
        self.last = now
        total = self.lo + (self.hi - self.lo) * max(0.0, min(1.0, frac))
        filled = int(total * 30)
        bar = "#" * filled + "-" * (30 - filled)
        text = "\r    [%s] %3d%%  %s %s  %d초" % (bar, int(total * 100), self.label, detail,
                                                 now - self.start)
        self._write(text + " " * 10)

    def finish(self, message):
        self._write("\r" + " " * 100 + "\r    " + message + "\n")


def log(*args):
    # 로그 파일(stdout)에 UTF-8 로 직접 쓴다 (print 는 콘솔 인코딩에 따라 한글에서 오류가 남)
    try:
        os.write(1, (" ".join(str(a) for a in args) + "\n").encode("utf-8"))
    except Exception:
        pass


# --------------------------------------------------------------------------
# 기본 방식: FreeCAD 의 "메쉬로부터 형상 만들기" 와 같다 (삼각형 하나 = 면 하나)
# --------------------------------------------------------------------------
def basic_convert(mesh):
    import Part
    shape = Part.Shape()
    shape.makeShapeFromMesh(mesh.Topology, 0.1)
    result = []
    for shell in shape.Shells:
        if shell.isClosed():
            solid = Part.Solid(shell)
            if solid.Volume < 0:
                solid = Part.Solid(shell.reversed())
            result.append(solid)
        else:
            result.append(shell)
    return result


# --------------------------------------------------------------------------
# 개선 방식: 평면 영역을 큰 면 하나로 합쳐서 만든다
# --------------------------------------------------------------------------
class Failed(Exception):
    pass


def smart_convert(mesh, prog, lo, hi):
    import numpy as np
    import Part
    import FreeCAD as App

    span = hi - lo

    def sub(a, b):
        return lo + span * a, lo + span * b

    pts, fac = mesh.Topology
    P = np.array([(p.x, p.y, p.z) for p in pts], dtype=float)
    F = np.array(fac, dtype=np.int64)
    nv, nf = len(P), len(F)
    if nf < 1:
        raise Failed("no facets")

    diag = float(np.linalg.norm(P.max(0) - P.min(0)))
    tol = max(diag * DIST_TOL_REL, 1e-12)
    cos_tol = math.cos(math.radians(ANGLE_TOL_DEG))

    # ---- 삼각형 법선/넓이 ----
    cr = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
    ln = np.linalg.norm(cr, axis=1)
    A = 0.5 * ln
    N = cr / np.where(ln > 0, ln, 1.0)[:, None]

    # ---- 이웃 관계 (모서리를 공유하는 삼각형) ----
    he = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    hf = np.concatenate([np.arange(nf)] * 3)
    ek = np.sort(he, axis=1)
    key = ek[:, 0] * nv + ek[:, 1]
    order = np.argsort(key, kind="stable")
    ks = key[order]
    starts = np.flatnonzero(np.r_[True, ks[1:] != ks[:-1]])
    counts = np.diff(np.r_[starts, len(ks)])

    bad_vertex = np.zeros(nv, dtype=bool)   # 열린 테두리/비다양체 모서리에 닿은 점
    odd = starts[counts != 2]
    if len(odd):
        bad_keys = ks[odd]
        bad_vertex[bad_keys // nv] = True
        bad_vertex[bad_keys % nv] = True

    nbrs = [[] for _ in range(nf)]
    two = starts[counts == 2]
    f1 = hf[order[two]].tolist()
    f2 = hf[order[two + 1]].tolist()
    for a, b in zip(f1, f2):
        nbrs[a].append(b)
        nbrs[b].append(a)

    # ---- 1) 평면 영역 묶기 (가장 큰 삼각형부터 씨앗으로 넓혀 나감) ----
    prog.stage(*sub(0.0, 0.15), label="평면 찾는 중")
    Nl = N.tolist()
    Pl = P.tolist()
    Fl = F.tolist()
    region = [-1] * nf
    regions = []
    done = 0
    for s in np.argsort(-A).tolist():
        if region[s] >= 0:
            continue
        rid = len(regions)
        region[s] = rid
        members = [s]
        if A[s] > 0:
            n0 = Nl[s]
            p0 = Pl[Fl[s][0]]
            d0 = n0[0] * p0[0] + n0[1] * p0[1] + n0[2] * p0[2]
            stack = [s]
            while stack:
                f = stack.pop()
                for g in nbrs[f]:
                    if region[g] >= 0:
                        continue
                    ng = Nl[g]
                    if ng[0] * n0[0] + ng[1] * n0[1] + ng[2] * n0[2] < cos_tol:
                        continue
                    ok = True
                    for v in Fl[g]:
                        q = Pl[v]
                        if abs(n0[0] * q[0] + n0[1] * q[1] + n0[2] * q[2] - d0) > tol:
                            ok = False
                            break
                    if ok:
                        region[g] = rid
                        members.append(g)
                        stack.append(g)
        regions.append(members)
        done += len(members)
        prog.update(done / nf)

    # ---- 2) 점을 평면 위로 정확히 맞추기 ----
    prog.stage(*sub(0.15, 0.25), label="평면 정리 중")
    multi = [r for r in range(len(regions)) if len(regions[r]) >= 2]
    plane = {}
    verts_of = {}
    vplanes = {}
    for r in multi:
        mem = np.array(regions[r])
        n = (N[mem] * A[mem][:, None]).sum(0)
        n /= np.linalg.norm(n)
        vs = np.unique(F[mem].ravel())
        d = float(np.dot(P[vs].mean(0), n))
        plane[r] = (n, d)
        verts_of[r] = vs
        for v in vs.tolist():
            vplanes.setdefault(v, []).append(r)

    def dissolve(r):
        mem = regions[r]
        regions[r] = mem[:1]
        for f in mem[1:]:
            region[f] = len(regions)
            regions.append([f])

    # 여러 평면이 만나는 점은 모든 평면 위에 동시에 놓여야 한다.
    # 그럴 수 없으면(거의 평행한 작은 평면이 끼어 있는 경우 등) 가장 작은 평면 묶음을 풀어
    # 원래 삼각형으로 되돌리고 다시 계산한다.
    eps = 1e-9 * max(diag, 1e-9)
    alive = set(multi)
    newpos = {}
    for _ in range(8):
        newpos = {}
        marks = set()
        for v, rs in vplanes.items():
            rs = [r for r in rs if r in alive]
            if len(rs) < 2:
                continue
            x = P[v]
            M = np.array([plane[r][0] for r in rs])
            b = np.array([plane[r][1] for r in rs])
            dx = np.linalg.lstsq(M, b - M @ x, rcond=None)[0]
            res = np.abs(M @ (x + dx) - b).max()
            if res > eps or np.linalg.norm(dx) > 3 * tol:
                marks.add(min(rs, key=lambda r: len(regions[r])))
            else:
                newpos[v] = x + dx
        if not marks:
            break
        for r in marks:
            dissolve(r)
            alive.discard(r)
        prog.update(0.3)

    for v, rs in vplanes.items():
        rs = [r for r in rs if r in alive]
        if len(rs) == 1:
            n, d = plane[rs[0]]
            P[v] = P[v] - (np.dot(n, P[v]) - d) * n
        elif len(rs) > 1 and v in newpos:
            P[v] = newpos[v]

    for r in list(alive):
        n, d = plane[r]
        if np.abs(P[verts_of[r]] @ n - d).max() > 10 * eps:
            dissolve(r)
            alive.discard(r)
    prog.update(0.5)

    # ---- 3) 영역 테두리 선(loop) 구하기 ----
    loops = {}
    multi = [r for r in multi if len(regions[r]) >= 2]
    for i, r in enumerate(multi):
        hs = set()
        for f in regions[r]:
            a, b, c = Fl[f]
            hs.add((a, b))
            hs.add((b, c))
            hs.add((c, a))
        nxt = {}
        ok = True
        for a, b in hs:
            if (b, a) in hs:
                continue
            if a in nxt:
                ok = False
                break
            nxt[a] = b
        rl = []
        if ok:
            n = plane[r][0]
            while nxt:
                start = next(iter(nxt))
                loop = [start]
                v = nxt.pop(start)
                while v != start:
                    loop.append(v)
                    if v not in nxt:
                        ok = False
                        break
                    v = nxt.pop(v)
                if not ok:
                    break
                q = P[loop]
                area = 0.5 * float(np.dot(np.cross(q, np.roll(q, -1, axis=0)).sum(0), n))
                rl.append((area, loop))
        if ok and sum(1 for a, _ in rl if a > 0) == 1:
            rl.sort(key=lambda t: -t[0])
            loops[r] = [lp for _, lp in rl]
        else:
            dissolve(r)
        if i % 200 == 0:
            prog.update(0.5 + 0.5 * i / max(1, len(multi)))

    # ---- 두 평면 사이 직선 위의 중간 점 제거 대상 찾기 ----
    R = np.array(region)
    size = np.array([len(m) for m in regions])
    vr = np.unique(np.stack([F.ravel(), np.repeat(R, 3)], 1), axis=0)
    nreg = np.bincount(vr[:, 0], minlength=nv)
    minsize = np.full(nv, 1 << 30)
    np.minimum.at(minsize, vr[:, 0], size[vr[:, 1]])
    candidate = (nreg == 2) & (minsize >= 2) & (~bad_vertex)

    removable = {}

    def keep_mask(loop):
        q = P[loop]
        prev = np.roll(q, 1, axis=0)
        nxt_ = np.roll(q, -1, axis=0)
        u = q - prev
        w = nxt_ - q
        c = np.linalg.norm(np.cross(u, w), axis=1)
        s = np.linalg.norm(u, axis=1) * np.linalg.norm(w, axis=1)
        straight = c <= 1e-6 * np.maximum(s, 1e-300)
        keep = []
        for v, st in zip(loop, straight.tolist()):
            if candidate[v]:
                if v not in removable:
                    removable[v] = st
                keep.append(not removable[v])
            else:
                keep.append(True)
        return keep

    final_loops = {}
    for r, lps in loops.items():
        if len(regions[r]) < 2:
            continue
        out = []
        for lp in lps:
            km = keep_mask(lp)
            red = [v for v, k in zip(lp, km) if k]
            if len(red) < 3:
                raise Failed("degenerate loop")
            out.append(red)
        final_loops[r] = out

    # ---- 4) 면 만들기 (모서리 공유) ----
    prog.stage(*sub(0.25, 0.8), label="면 만드는 중")
    VX = {}
    ED = {}

    def vertex(v):
        x = VX.get(v)
        if x is None:
            x = Part.Vertex(App.Vector(*P[v]))
            VX[v] = x
        return x

    def edge(a, b):
        k = (a, b) if a < b else (b, a)
        e = ED.get(k)
        if e is None:
            e = Part.Edge(vertex(k[0]), vertex(k[1]))
            ED[k] = e
        return e

    def wire(loop):
        return Part.Wire([edge(loop[i], loop[(i + 1) % len(loop)]) for i in range(len(loop))])

    faces = []
    nreg_total = len(regions)
    planes_merged = 0
    for i, mem in enumerate(regions):
        if len(mem) >= 2:
            n, d = plane[i]
            lps = final_loops[i]
            nvec = App.Vector(*n)
            # 바깥 테두리로 면을 만든 뒤 구멍을 뚫는다. 모서리를 공유하느라 선 방향이
            # 제각각이라 실패할 수 있는데, 그때만 느린 면 보정(validate)을 쓴다.
            face = None
            try:
                face = Part.Face(wire(lps[0]))
                if len(lps) > 1:
                    # 구멍 테두리는 바깥 테두리와 반대 방향이어야 한다
                    up = face.normalAt(0, 0)
                    holes = []
                    for lp in lps[1:]:
                        hw = wire(lp)
                        if Part.Face(hw).normalAt(0, 0).dot(up) > 0:
                            hw = hw.reversed()
                        holes.append(hw)
                    face.cutHoles(holes)
                if not face.isValid():
                    face = None
            except Exception:
                face = None
            if face is None:
                face = Part.Face(Part.Plane(App.Vector(*(n * d)), nvec), [wire(lp) for lp in lps])
                face.validate()
            planes_merged += 1
        else:
            a, b, c = Fl[mem[0]]
            face = Part.Face(wire([a, b, c]))
            pa, pb, pc = P[a], P[b], P[c]
            nvec = App.Vector(*np.cross(pb - pa, pc - pa))
        u0, u1, v0, v1 = face.ParameterRange
        if face.normalAt((u0 + u1) / 2, (v0 + v1) / 2).dot(nvec) < 0:
            face.reverse()
        faces.append(face)
        if i % 200 == 0:
            prog.update(i / nreg_total, detail="(%d / %d)" % (i, nreg_total))

    # ---- 5) 셸 -> 솔리드 ----
    if len(odd):
        # 열린 테두리나 3개 이상의 면이 공유하는 모서리가 있으면 솔리드가 될 수 없다.
        # 이런 메쉬는 FreeCAD 에서 셸로 잇는 데 수십 분이 걸리므로(3DBenchy: 30개 모서리 때문에
        # 11분 이상) 면 묶음으로 그대로 내보낸다.
        log("smart: open/non-manifold edges=%d -> faces exported as a compound" % len(odd))
        log("smart: triangles=%d faces=%d merged_planes=%d" % (nf, len(faces), planes_merged))
        return Part.Compound(faces), nf, len(faces)

    prog.stage(*sub(0.8, 0.95), label="면 잇는 중")
    shell = Part.Shell(faces)
    prog.stage(*sub(0.95, 1.0), label="솔리드로 만드는 중")
    if shell.isClosed():
        solid = Part.Solid(shell)
        if solid.Volume < 0:
            solid = Part.Solid(shell.reversed())
        if not solid.isValid():
            raise Failed("invalid solid")
        mv = abs(mesh.Volume)
        if mv > 0 and abs(solid.Volume - mv) / mv > VOLUME_TOL:
            raise Failed("volume mismatch %.4f vs %.4f" % (solid.Volume, mv))
        result = solid
    else:
        if not shell.isValid():
            raise Failed("invalid open shell")
        result = shell
    log("smart: triangles=%d faces=%d merged_planes=%d" % (nf, len(faces), planes_merged))
    return result, nf, len(faces)


def main():
    import Mesh
    import Part

    src = os.environ["STL2STEP_IN"]
    dst = os.environ["STL2STEP_OUT"]
    prog = Progress()
    t0 = time.time()

    prog.stage(0.0, 0.05, "STL 읽는 중")
    mesh = Mesh.Mesh(src)
    for fix in ("removeDuplicatedPoints", "removeDuplicatedFacets", "harmonizeNormals"):
        try:
            getattr(mesh, fix)()
        except Exception:
            log("mesh fix failed:", fix)
    try:
        if mesh.isSolid() and mesh.Volume < 0:
            mesh.flipNormals()
    except Exception:
        pass
    total = max(1, mesh.CountFacets)
    log("triangles:", mesh.CountFacets)

    parts = mesh.getSeparateComponents() or [mesh]
    shapes = []
    tri_count = face_count = 0
    pos = 0.05
    used_basic = False
    for comp in parts:
        share = 0.85 * comp.CountFacets / total
        try:
            shape, nt, nfc = smart_convert(comp, prog, pos, pos + share)
            shapes.append(shape)
            tri_count += nt
            face_count += nfc
        except Exception as e:
            log("smart convert failed, using basic:", repr(e))
            log(traceback.format_exc())
            prog.stage(pos, pos + share, "기본 방식으로 변환 중")
            basic = basic_convert(comp)
            shapes.extend(basic)
            tri_count += comp.CountFacets
            face_count += sum(len(s.Faces) for s in basic)
            used_basic = True
        pos += share

    prog.stage(0.9, 1.0, "STEP 저장 중")
    out = shapes[0] if len(shapes) == 1 else Part.Compound(shapes)
    # copy() 로 FreeCAD 의 요소 이름 정보를 떼어내면 저장이 몇 배 빨라진다
    out.copy().exportStep(dst)

    msg = "삼각형 %s개 -> 면 %s개, %.1f초" % (format(tri_count, ","), format(face_count, ","), time.time() - t0)
    if used_basic:
        msg += " (일부는 기본 방식으로 변환)"
    prog.finish(msg)
    log(msg)


code = 0
try:
    main()
except Exception:
    traceback.print_exc()
    code = 1
try:
    sys.stdout.flush()
    sys.stderr.flush()
except Exception:
    pass
os._exit(code)
