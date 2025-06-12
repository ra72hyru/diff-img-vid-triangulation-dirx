ByteAddressBuffer positions : register(t0);
ByteAddressBuffer indices : register(t1);
ByteAddressBuffer colors : register(t2);
Texture2D image : register(t3);

RWByteAddressBuffer gradients : register(u0);

int intersect_segments(float2 o1, float2 d1, float2 o2, float2 d2, out float2 i0, out float2 i1)
{
    float2 w = o1 - o2;
    float D = cross(float3(d1, 0), float3(d2, 0)).z;
    i0 = float2(-1, -1);
    i1 = float2(-1, -1);
    if (abs(D) < 1E-5)
    {
        float para1 = cross(float3(d1, 0), float3(w, 0)).z;
        float para2 = cross(float3(d2, 0), float3(w, 0)).z;
        if (para1 != 0 || para2 != 0)
        {
            return 0;
        }

        float t0;
        float t1;

        float2 w2 = o1 + d1 - o2;
        if (d2.x != 0)
        {
            t0 = w.x / d2.x;
            t1 = w2.x / d2.x;
        }
        else
        {
            t0 = w.y / d2.y;
            t1 = w2.y / d2.y;
        }

        if (t0 > t1)
        {
            float tmp = t1;
            t1 = t0;
            t0 = tmp;
        }

        if (t0 > 1 || t1 > 1)
        {
            return 0;
        }

        t0 < 0 ? 0 : t0;
        t1 > 1 ? 1 : t1;

        if (t0 == t1)
        {
            i0 = o2 + t0 * d2;
            return 1;
        }

        i0 = o2 + t0 * d2;
        i1 = o2 + t1 * d2;
        return 2;
    }

    float sI = cross(float3(w, 0), float3(d2, 0)).z / -D;
    if (sI < 0 || sI > 1)//(sI <= 1E-5 || sI >= 0.99999)
    {
        return 0;
    }

    float tI = cross(float3(d1, 0), float3(w, 0)).z / D;
    if (tI < 0 || tI > 1)//(tI <= 1E-5 || tI >= 0.9999)
    {
        return 0;
    }

    i0 = o1 + sI * d1;
    return 1;
}

float2 normal_out(float2 v, float2 w)
{
    float2 n = float2(v.y, -v.x);
    if (dot(n, w) > 0)
        return -n;
    return n;
}

float3 integrate(float3 K, float3 Kx, float3 Ky, float3 Kxy, float c, float d, float2 B, float2 bc, float3 tri_color)
{
    float3 K2 = pow(K, 2);
    float3 Kx2 = pow(Kx, 2);
    float3 Ky2 = pow(Ky, 2);
    float3 Kxy2 = pow(Kxy, 2);
    
    float3 t2 = 0.5 * (d * d - c * c) * (K2 + Kx2 * B.x * B.x + Ky2 * B.y * B.y + Kxy2 * B.x * B.x * B.y * B.y - 2 * K * tri_color - 2 * Kx * B.x * tri_color - 2 * Ky * B.y * tri_color - 2 * Kxy * B.x * B.y * tri_color + pow(tri_color, 2) + 2 * K * Kx * B.x + 2 * K * Ky * B.y + 2 * K * Kxy * B.x * B.y + 2 * Kx * Ky * B.x * B.y + 2 * Kx * Kxy * B.x * B.x * B.y + 2 * Ky * Kxy * B.x * B.y * B.y);
    float3 t3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (Kx2 * 2 * B.x * bc.x + Ky2 * 2 * B.y * bc.y + Kxy2 * 2 * B.x * B.x * B.y * bc.y + Kxy2 * 2 * B.x * B.y * B.y * bc.x - 2 * Kx * bc.x * tri_color - 2 * Ky * bc.y * tri_color - 2 * Kxy * B.x * bc.y * tri_color - 2 * Kxy * B.y * bc.x * tri_color + 2 * K * Kx * bc.x + 2 * K * Ky * bc.y + 2 * K * Kxy * (B.x * bc.y + B.y * bc.x) + 2 * Kx * Ky * (B.x * bc.y + B.y * bc.x) + 2 * Kx * Kxy * (B.x * B.x * bc.y + 2 * B.x * B.y * bc.x) + 2 * Ky * Kxy * (2 * B.x * B.y * bc.y + B.y * B.y * bc.x));
    float3 t4 = 0.25 * (d * d * d * d - c * c * c * c) * (Kx2 * bc.x * bc.x + Ky2 * bc.y * bc.y + Kxy2 * B.x * B.x * bc.y * bc.y + Kxy2 * 4 * B.x * B.y * bc.x * bc.y + Kxy2 * B.y * B.y * bc.x * bc.x - 2 * Kxy * bc.x * bc.y * tri_color + 2 * K * Kxy * (bc.x * bc.y) + 2 * Kx * Ky * bc.x * bc.y + 2 * Kx * Kxy * (2 * B.x * bc.x * bc.y + B.y * bc.x * bc.x) + 2 * Ky * Kxy * (B.x * bc.y * bc.y + 2 * B.y * bc.x * bc.y));
    float3 t5 = 0.2 * (d * d * d * d * d - c * c * c * c * c) * (Kxy2 * 2 * B.x * bc.x * bc.y * bc.y + Kxy2 * 2 * B.y * bc.x * bc.x * bc.y + 2 * Kx * Kxy * bc.x * bc.x * bc.y + 2 * Ky * Kxy * bc.x * bc.y * bc.y);
    float3 t6 = 1.0 / 6.0 * (d * d * d * d * d * d - c * c * c * c * c * c) * (Kxy2 * bc.x * bc.x * bc.y * bc.y);

    return t2 + t3 + t4 + t5 + t6;
}

void load(float curLR, float curBU, out float3 K, out float3 Kx, out float3 Ky, out float3 Kxy)
{
    int curX = (int) floor(curLR);
    int curY = (int) floor(curBU);
    int lr = abs(curLR - (float) curX) > 1E-5 ? 1 : 0;
    int bu = abs(curBU - (float) curY) > 1E-5 ? 1 : 0;
        
    float x1 = lr == 0 ? curLR - 0.5 : curLR;
    float y1 = bu == 0 ? curBU - 0.5 : curBU;
    float x2 = lr == 0 ? curLR + 0.5 : curLR + 1;
    float y2 = bu == 0 ? curBU + 0.5 : curBU + 1;
    
    float3 bl = image.Load(int3(curX + lr - 1, curY + bu - 1, 0));
    float3 br = image.Load(int3(curX + lr, curY + bu - 1, 0));
    float3 tl = image.Load(int3(curX + lr - 1, curY + bu, 0));
    float3 tr = image.Load(int3(curX + lr, curY + bu, 0));
    
    K = bl * x2 * y2 - br * x1 * y2 - tl * x2 * y1 + tr * x1 * y1;
    Kx = -bl * y2 + br * y2 + tl * y1 - tr * y1;
    Ky = -bl * x2 + br * x1 + tl * x2 - tr * x1;
    Kxy = bl - br - tl + tr;
}

void gradient_rtt(float3 tri_color, float2 A, float2 B, float2 C, float dx, float dy, inout float2 gradABC, inout float2 gradACB, inout float2 gradBCA)
{
    float2 ba = A - B;
    float2 ac = C - A;
    float2 bc = C - B;
    float2 ab = B - A;
    
    float length_bc = length(bc);
    float length_ac = length(ac);
    float length_ab = length(ab);
    
    float2 n_bc = normalize(normal_out(bc, ba));
    float2 n_ac = normalize(normal_out(ac, -ba));
    float2 n_ab = normalize(normal_out(ab, ac));
    
    int f_right_x = 1, f_right_y = 1;
    float2 n = -normal_out(bc, ba);
    f_right_x = (dot(n, float2(1, 0)) > 0) ? -1 : f_right_x;
    f_right_y = (dot(n, float2(0, 1)) > 0) ? -1 : f_right_y;
    
    int f_left_x = 1, f_left_y = 1;
    n = -normal_out(ac, -ba);
    f_left_x = (dot(n, float2(1, 0)) > 0) ? -1 : f_left_x;
    f_left_y = (dot(n, float2(0, 1)) > 0) ? -1 : f_left_y;

    int f_ab_x = 1, f_ab_y = 1;
    n = -normal_out(ab, ac);
    f_ab_x = (dot(n, float2(1, 0)) > 0) ? -1 : f_ab_x;
    f_ab_y = (dot(n, float2(0, 1)) > 0) ? -1 : f_ab_y;
    
    gradABC = float2(0.0, 0.0);
    gradACB = float2(0.0, 0.0);
    gradBCA = float2(0.0, 0.0);

    int left, bottom;
    
    int curX = floor(B.x);
    int curY = floor(B.y);
    int endX = floor(C.x);
    int endY = floor(C.y);
    
    float curLR = (B.x - floor(B.x) < 0.5) ? floor(B.x) : floor(B.x) + 0.5;
    float curBU = (B.y - floor(B.y) < 0.5) ? floor(B.y) : floor(B.y) + 0.5;
    float endLR = (C.x - floor(C.x) < 0.5) ? floor(C.x) : floor(C.x) + 0.5;
    float endBU = (C.y - floor(C.y) < 0.5) ? floor(C.y) : floor(C.y) + 0.5;
    
    float2 p = B;
    float2 q;
    
    float2 i0 = float2(0, 0), i1 = float2(0, 0);
    int intrsct;
    float a = 0, b = 0, c = 0, d = 1, err = 0.0f;
    float3 img_col, err3;
    float3 K, Kx, Ky, Kxy, integral;
    bool4 last_pixel = bool4(false, false, false, false); //Bottom, Top, Left, Right
    
    last_pixel.x = B.y < C.y ? true : false;
    last_pixel.y = B.y > C.y ? true : false;
    last_pixel.z = B.x < C.x ? true : false; 
    last_pixel.w = B.x > C.x ? true : false;
        
    int3 dimensions;
    image.GetDimensions(0, dimensions.x, dimensions.y, dimensions.z);
    dimensions.x -= 1;
    dimensions.y -= 1;
    
    int bu = 0;
    int lr = 0;
    
    float x1, x2, y1, y2;
    float3 col_bl, col_bm, col_br, col_ml, col_mm, col_mr, col_tl, col_tm, col_tr;
    
    const float eps = 1E-5;
    int test = 0;
    while ( /*test < 5 &&*/((curLR - endLR) > eps || (curBU - endBU) > eps))
    {
        /*
        curX = (int) floor(curLR);
        curY = (int) floor(curBU);
        lr = curLR - curX > eps ? 1 : 0;
        bu = curBU - curY > eps ? 1 : 0;
        
        x1 = lr == 0 ? curLR - 0.5 : curLR;
        y1 = bu == 0 ? curBU - 0.5 : curBU;
        x2 = lr == 0 ? curLR + 0.5 : curLR + 1;
        y2 = bu == 0 ? curBU + 0.5 : curBU + 1;
        
        col_bl = image.Load(int3(max(0, curX - 1), max(0, curY - 1), 0));
        col_bm = image.Load(int3(curX, max(0, curY - 1), 0));
        col_br = image.Load(int3(min(dimensions.x, curX + 1), max(0, curY - 1), 0));
        col_ml = image.Load(int3(max(0, curX - 1), curY, 0));
        col_mm = image.Load(int3(curX, curY, 0));
        col_mr = image.Load(int3(min(dimensions.x, curX + 1), curY, 0));
        col_tl = image.Load(int3(max(0, curX - 1), min(dimensions.y, curY + 1), 0));
        col_tm = image.Load(int3(curX, min(dimensions.y, curY + 1), 0));
        col_tr = image.Load(int3(min(dimensions.x, curX + 1), min(dimensions.y, curY + 1), 0));
        float3 cols[9] =
        {
            col_bl, col_bm, col_br,
                col_ml, col_mm, col_mr,
                col_tl, col_tm, col_tr
        };
        K = cols[0 + bu * 3 + lr * 1].xyz * x2 * y2
                            - cols[1 + bu * 3 + lr * 1].xyz * x1 * y2
                            - cols[3 + bu * 3 + lr * 1].xyz * x2 * y1
                            + cols[4 + bu * 3 + lr * 1].xyz * x1 * y1;
                        
        Kx = -cols[0 + bu * 3 + lr * 1].xyz * y2
                            + cols[1 + bu * 3 + lr * 1].xyz * y2
                            + cols[3 + bu * 3 + lr * 1].xyz * y1
                            - cols[4 + bu * 3 + lr * 1].xyz * y1;
                        
        Ky = -cols[0 + bu * 3 + lr * 1].xyz * x2
                            + cols[1 + bu * 3 + lr * 1].xyz * x1
                            + cols[3 + bu * 3 + lr * 1].xyz * x2
                            - cols[4 + bu * 3 + lr * 1].xyz * x1;
                        
        Kxy = cols[0 + bu * 3 + lr * 1].xyz
                            - cols[1 + bu * 3 + lr * 1].xyz
                            - cols[3 + bu * 3 + lr * 1].xyz
                            + cols[4 + bu * 3 + lr * 1].xyz;
        
        */

        load(curLR, curBU, K, Kx, Ky, Kxy);
        
        if (!last_pixel.x)
        {
            intrsct = intersect_segments(B, bc, float2(curLR, curBU), float2(0.5, 0), i0, i1);
            if (intrsct == 1)
            {
                //continue;
                q = i0;
                b = length(p - B) / length_bc;
                c = length(p - C) / length_bc;
                
                //gradABC += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
                integral = integrate(K, Kx, Ky, Kxy, a, b, B, bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
                //gradACB += err * abs(length_bc * (0.5f * (d * d - c * c) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
                
                
                p = q;
                a = b;
                d = c;
                curBU -= 0.5;
                last_pixel.y = true; //bool4(false, true, false, false);
                //curX = endX;
                //curY = endY;
                continue;
            }
            else if (intrsct == 2)
            {
                //continue;
                p = i0;
                q = i1;
            
                b = length(p - B) / length_bc;
                a = length(q - B) / length_bc;
                d = length(p - C) / length_bc;
                c = length(q - C) / length_bc;
            
                integral = integrate(K, Kx, Ky, Kxy, a, b, B, bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
            
                curLR = (B.x < C.x) ? curLR + 0.5 : curLR - 0.5;
                //curX = endX;
                //curY = endY;
                continue;
            }
        }
        
        if (!last_pixel.z)
        {
            intrsct = intersect_segments(B, bc, float2(curLR, curBU), float2(0, 0.5), i0, i1);
            
            if (intrsct == 1)
            {
                //continue;
                q = i0;
                b = length(p - B) / length_bc;
                c = length(p - C) / length_bc;
                
                integral = integrate(K, Kx, Ky, Kxy, a, b, B, bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curLR -= 0.5;
                last_pixel.w = true; //bool4(false, false, false, true);
                //curX = endX;
                //curY = endY;
                continue;
            }
            else if (intrsct == 2)
            {
                //continue;
                p = i0;
                q = i1;
            
                b = length(p - B) / length_bc;
                a = length(q - B) / length_bc;
                d = length(p - C) / length_bc;
                c = length(q - C) / length_bc;
            
                integral = integrate(K, Kx, Ky, Kxy, a, b, B, bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
            
                curBU = (B.y < C.y) ? curBU + 0.5 : curBU - 0.5;
                //curY = endY;
                //curX = endX;
                continue;
            }
        }

        if (!last_pixel.w)
        {
            intrsct = intersect_segments(B, bc, float2(curLR + 1, curBU), float2(0, 0.5), i0, i1);
            
            if (intrsct == 1)
            {
                //continue;
                q = i0;
                b = length(p - B) / length_bc;
                c = length(p - C) / length_bc;
                
                integral = integrate(K, Kx, Ky, Kxy, a, b, B, bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curLR += 0.5;
                last_pixel.z = true; //bool4(false, false, true, false);
                //curX = endX;
                //curY = endY;
                continue;
            }
            else if (intrsct == 2)
            {
                //continue;
                p = i0;
                q = i1;
            
                b = length(p - B) / length_bc;
                a = length(q - B) / length_bc;
                d = length(p - C) / length_bc;
                c = length(q - C) / length_bc;
            
                integral = integrate(K, Kx, Ky, Kxy, a, b, B, bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
            
                curBU = (B.y < C.y) ? curBU + 0.5 : curBU - 0.5;
                //curY = endY;
                curLR += 0.5;
                continue;
            }
        }
        
        if (!last_pixel.y)
        {
            intrsct = intersect_segments(B, bc, float2(curLR, curBU + 0.5), float2(0.5, 0), i0, i1);
            
            if (intrsct == 1)
            {
                //continue;
                q = i0;
                b = length(p - B) / length_bc;
                c = length(p - C) / length_bc;
                
                integral = integrate(K, Kx, Ky, Kxy, a, b, B, bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curBU += 0.5;
                last_pixel.x = true; //bool4(true, false, false, false);
                //curX = endX;
                //curY = endY;
                continue;
            }
            else if (intrsct == 2)
            {
                //continue;
                p = i0;
                q = i1;
            
                b = length(p - B) / length_bc;
                a = length(q - B) / length_bc;
                d = length(p - C) / length_bc;
                c = length(q - C) / length_bc;
            
                integral = integrate(K, Kx, Ky, Kxy, a, b, B, bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -bc, tri_color);
                integral = abs(length_bc * n_bc.x * integral) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * integral) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
            
                curLR = (B.x < C.x) ? curLR + 0.5 : curLR - 0.5;
                //curX = endX;
                curBU += 0.5;
                continue;
            }
        }
        break;
    }
    //if (curX < 0 || curY < 0)
      //  gradABC = 19283746;

    load(curLR, curBU, K, Kx, Ky, Kxy);
    
    a = max(a, b);
    b = 1.0f;
    d = min(c, d);
    c = 0.0f;
    
    integral = integrate(K, Kx, Ky, Kxy, a, b, B, bc, tri_color);
    integral = abs(length_bc * n_bc.x * integral) * f_right_x;
    gradABC.x += integral.x + integral.y + integral.z;
    integral = abs(length_bc * n_bc.y * integral) * f_right_y;
    gradABC.y += integral.x + integral.y + integral.z;
                
    integral = integrate(K, Kx, Ky, Kxy, c, d, C, -bc, tri_color);
    integral = abs(length_bc * n_bc.x * integral) * f_right_x;
    gradACB.x += integral.x + integral.y + integral.z;
    integral = abs(length_bc * n_bc.y * integral) * f_right_y;
    gradACB.y += integral.x + integral.y + integral.z;
    
    //reset variables
    //curX = floor(A.x);
    //curY = floor(A.y);
    curLR = (A.x - floor(A.x) < 0.5) ? floor(A.x) : floor(A.x) + 0.5;
    curBU = (A.y - floor(A.y) < 0.5) ? floor(A.y) : floor(A.y) + 0.5;
    a = 0, b = 0, c = 0, d = 1;
    p = A;
    
    last_pixel.x = A.y < C.y ? true : false;
    last_pixel.y = A.y > C.y ? true : false;
    last_pixel.z = A.x < C.x ? true : false;
    last_pixel.w = A.x > C.x ? true : false;
    
    test = 0;
    
    while ( /*test < 50 && */((curLR - endLR) > eps || (curBU - endBU) > eps))
    {
        load(curLR, curBU, K, Kx, Ky, Kxy);
        //test++;
        if (!last_pixel.x)
        {
            intrsct = intersect_segments(A, ac, float2(curLR, curBU), float2(0.5, 0), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ac;
                c = length(p - C) / length_ac;
                
                //gradABC += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
                //gradBCA += err * abs(length_ac * (0.5f * (d * d - c * c) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
                
                p = q;
                a = b;
                d = c;
                curBU -= 0.5;
                last_pixel.y = true;
                continue;
            }
            else if (intrsct == 2)
            {
                p = i0;
                q = i1;
            
                b = length(p - A) / length_ac;
                a = length(q - A) / length_ac;
                d = length(p - C) / length_ac;
                c = length(q - C) / length_ac;
            
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curLR = A.x < C.x ? curLR + 0.5 : curLR - 0.5;
                continue;
            }
        }
        
        if (!last_pixel.z)
        {
            intrsct = intersect_segments(A, ac, float2(curLR, curBU), float2(0, 0.5), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ac;
                c = length(p - C) / length_ac;
                
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curLR -= 0.5;
                last_pixel.w = true;
                continue;
            }
            else if (intrsct == 2)
            {
                p = i0;
                q = i1;
            
                b = length(p - A) / length_ac;
                a = length(q - A) / length_ac;
                d = length(p - C) / length_ac;
                c = length(q - C) / length_ac;
            
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curBU = A.y < C.y ? curBU + 0.5 : curBU - 0.5;
                continue;
            }
        }
        
        if (!last_pixel.w)
        {
            intrsct = intersect_segments(A, ac, float2(curLR + 0.5, curBU), float2(0, 0.5), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ac;
                c = length(p - C) / length_ac;
                
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curLR += 0.5;
                last_pixel.z = true;
                continue;
            }
            else if (intrsct == 2)
            {
                p = i0;
                q = i1;
            
                b = length(p - A) / length_ac;
                a = length(q - A) / length_ac;
                d = length(p - C) / length_ac;
                c = length(q - C) / length_ac;
            
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curBU = A.y < C.y ? curBU + 0.5 : curBU - 0.5;
                curLR += 0.5;
                continue;
            }
        }
        
        if (!last_pixel.y)
        {
            intrsct = intersect_segments(A, ac, float2(curLR, curBU + 0.5), float2(0.5, 0), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ac;
                c = length(p - C) / length_ac;
                
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curBU += 0.5;
                last_pixel.x = true;
                continue;
            }
            else if (intrsct == 2)
            {
                p = i0;
                q = i1;

                b = length(p - A) / length_ac;
                a = length(q - A) / length_ac;
                d = length(p - C) / length_ac;
                c = length(q - C) / length_ac;
            
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, C, -ac, tri_color);
                integral = abs(length_ac * n_ac.x * integral) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * integral) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curLR = A.x < C.x ? curLR + 0.5 : curLR - 0.5;
                curBU += 0.5;
                continue;
            }
        }
        break;
    }
    //if (curX < 0 || curY < 0)
      //  gradABC = 19283746;
    load(curLR, curBU, K, Kx, Ky, Kxy);
    a = max(a, b);
    b = 1.0f;
    d = min(c, d);
    c = 0.0f;
    integral = integrate(K, Kx, Ky, Kxy, a, b, A, ac, tri_color);
    integral = abs(length_ac * n_ac.x * integral) * f_left_x;
    gradABC.x += integral.x + integral.y + integral.z;
    integral = abs(length_ac * n_ac.y * integral) * f_left_y;
    gradABC.y += integral.x + integral.y + integral.z;

    integral = integrate(K, Kx, Ky, Kxy, c, d, C, -ac, tri_color);
    integral = abs(length_ac * n_ac.x * integral) * f_left_x;
    gradBCA.x += integral.x + integral.y + integral.z;
    integral = abs(length_ac * n_ac.y * integral) * f_left_y;
    gradBCA.y += integral.x + integral.y + integral.z;
    
    /*curX = floor(A.x);
    curY = floor(A.y);
    endX = floor(B.x);
    endY = floor(B.y);*/
    curLR = (A.x - floor(A.x) < 0.5) ? floor(A.x) : floor(A.x) + 0.5;
    curBU = (A.y - floor(A.y) < 0.5) ? floor(A.y) : floor(A.y) + 0.5;
    endLR = (B.x - floor(B.x) < 0.5) ? floor(B.x) : floor(B.x) + 0.5;
    endBU = (B.y - floor(B.y) < 0.5) ? floor(B.y) : floor(B.y) + 0.5;
    a = 0, b = 0, c = 0, d = 1;
    p = A;
    
    last_pixel.x = A.y < B.y ? true : false;
    last_pixel.y = A.y > B.y ? true : false;
    last_pixel.z = A.x < B.x ? true : false;
    last_pixel.w = A.x > B.x ? true : false;
    
    test = 0;
    
    while ( /*test < 50 &&*/((curLR - endLR) > eps || (curBU - endBU) > eps))
    {
        load(curLR, curBU, K, Kx, Ky, Kxy);
        //test++;
        if (!last_pixel.x)
        {
            intrsct = intersect_segments(A, ab, float2(curLR, curBU), float2(0.5, 0), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ab;
                c = length(p - B) / length_ab;
                
                //gradACB += err * abs(length_ab * (0.5f * (b * b - a * a) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
                //gradBCA += err * abs(length_ab * (0.5f * (d * d - c * c) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
            
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, B, -ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
                
                p = q;
                a = b;
                d = c;
                curBU -= 0.5;
                last_pixel.y = true;
                continue;
            }
            else if (intrsct == 2)
            {
                p = i0;
                q = i1;
            
                b = length(p - A) / length_ab;
                a = length(q - A) / length_ab;
                d = length(p - B) / length_ab;
                c = length(q - B) / length_ab;
            
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, B, -ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curLR = A.x < B.x ? curLR + 0.5 : curLR - 0.5;
                continue;
            }
        }
        
        if (!last_pixel.z)
        {
            intrsct = intersect_segments(A, ab, float2(curLR, curBU), float2(0, 0.5), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ab;
                c = length(p - B) / length_ab;
                
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, B, -ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curLR -= 0.5;
                last_pixel.w = true;
                continue;
            }
            else if (intrsct == 2)
            {
                p = i0;
                q = i1;
            
                b = length(p - A) / length_ab;
                a = length(q - A) / length_ab;
                d = length(p - B) / length_ab;
                c = length(q - B) / length_ab;
            
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, B, -ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curBU = A.y < B.y ? curBU + 0.5 : curBU - 0.5;
                continue;
            }
        }
        
        if (!last_pixel.w)
        {
            intrsct = intersect_segments(A, ab, float2(curLR + 0.5, curBU), float2(0, 0.5), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ab;
                c = length(p - B) / length_ab;
                
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, B, -ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curLR += 0.5;
                last_pixel.z = true;
                continue;
            }
            else if (intrsct == 2)
            {
                p = i0;
                q = i1;
            
                b = length(p - A) / length_ab;
                a = length(q - A) / length_ab;
                d = length(p - B) / length_ab;
                c = length(q - B) / length_ab;
            
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, B, -ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curBU = A.y < B.y ? curBU + 0.5 : curBU - 0.5;
                curLR += 0.5;
                continue;
            }
        }
        
        if (!last_pixel.y)
        {
            intrsct = intersect_segments(A, ab, float2(curLR, curBU + 0.5), float2(0.5, 0), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ab;
                c = length(p - B) / length_ab;
                
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, B, -ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curBU += 0.5;
                last_pixel.x = true;
                continue;
            }
            else if (intrsct == 2)
            {
                p = i0;
                q = i1;
            
                b = length(p - A) / length_ab;
                a = length(q - A) / length_ab;
                d = length(p - B) / length_ab;
                c = length(q - B) / length_ab;
            
                integral = integrate(K, Kx, Ky, Kxy, a, b, A, ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;

                integral = integrate(K, Kx, Ky, Kxy, c, d, B, -ab, tri_color);
                integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curLR = A.x < B.x ? curLR + 0.5 : curLR - 0.5;
                curBU += 0.5;
                continue;
            }
        }
        break;
    }
    //if (curX < 0 || curY < 0)
      //  gradABC = 19283746;
    load(curLR, curBU, K, Kx, Ky, Kxy);
    a = max(a, b);
    b = 1.0f;
    d = min(c, d);
    c = 0.0f;
    integral = integrate(K, Kx, Ky, Kxy, a, b, A, ab, tri_color);
    integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
    gradACB.x += integral.x + integral.y + integral.z;
    integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
    gradACB.y += integral.x + integral.y + integral.z;

    integral = integrate(K, Kx, Ky, Kxy, c, d, B, -ab, tri_color);
    integral = abs(length_ab * n_ab.x * integral) * f_ab_x;
    gradBCA.x += integral.x + integral.y + integral.z;
    integral = abs(length_ab * n_ab.y * integral) * f_ab_y;
    gradBCA.y += integral.x + integral.y + integral.z;
}

float test()
{
    /*float3 tri_col = float3(254.0f / 255.0f, 0, 0);
    float2 A = float2(0.0f, 0.0f);
    float2 B = float2(3.0f, 3.0f);
    loat2 C = float2(0.0f, 3.0f);*/
    float3 tri_col = float3(254.0f / 255.0f, 0, 0);
    float2 A = float2(700.0f, 500.0f);
    float2 B = float2(730.0f, 500.0f);
    float2 C = float2(730.0f, 530.0f);
    
    float2 grABC = float2(0.0f, 0.0f);
    float2 grACB = float2(0.0f, 0.0f);
    float2 grBCA = float2(0.0f, 0.0f);
    float grabcx = 0.0f;
    gradient_rtt(tri_col, A, B, C, 1.0f, 0.0f, grABC, grACB, grBCA);
    gradient_rtt(tri_col, A, B, C, 0.0f, 1.0f, grABC, grACB, grBCA);
    
    if (grABC.y != 0)//grABC.x != 0.0f)
    {
        return grBCA.x;
    }
    return grBCA.x;
}

[numthreads(32, 1, 1)]
void main(uint DTid : SV_DispatchThreadID)
{
    /*float tst = test();
    if (tst != 0.0f)
    {
        float3 img_col = image.Load(int3(2, 0, 0)).rgb;
        float3 err3 = pow(abs((img_col - float3(254.0f / 255.0f, 0, 0))), 2);
        float err = err3.x + err3.y + err3.z;
        gradients.Store2(DTid * 24, asint(float2(123456789.0f, 987654321.0f)));
        gradients.Store2(DTid * 24 + 8, asint(float2(123456789.0f, 987654321.0f)));
        gradients.Store2(DTid * 24 + 16, asint(float2(123456789.0f, 987654321.0f)));
        return;
    }*/
    
    uint ind_A = indices.Load(DTid * 12);
    uint ind_B = indices.Load(DTid * 12 + 4);
    uint ind_C = indices.Load(DTid * 12 + 8);
    
    float2 A = asfloat(positions.Load2(ind_A * 8));
    float2 B = asfloat(positions.Load2(ind_B * 8));
    float2 C = asfloat(positions.Load2(ind_C * 8));
    
    float3 tri_col = asfloat(colors.Load3(DTid * 12));
    
    float2 grABC = float2(0.0f, 0.0f);
    float2 grACB = float2(0.0f, 0.0f);
    float2 grBCA = float2(0.0f, 0.0f);
    
    gradient_rtt(tri_col, A, B, C, 1.0f, 0.0f, grABC, grACB, grBCA);
    //gradient_rtt(tri_col, A, B, C, 0.0f, 1.0f, grABC.y, grACB.y, grBCA.y);

    if (isnan(grABC.x))
        grABC.x = 0;
    if (isnan(grACB.x))
        grACB.x = 0;
    if (isnan(grBCA.x))
        grBCA.x = 0;
    if (isnan(grABC.y))
        grABC.y = 0;
    if (isnan(grACB.y))
        grACB.y = 0;
    if (isnan(grBCA.y))
        grBCA.y = 0;
    
    //grABC = float2(1, 2);
    gradients.Store2(DTid * 24, asint(grABC));
    gradients.Store2(DTid * 24 + 8, asint(grACB));
    gradients.Store2(DTid * 24 + 16, asint(grBCA));
}