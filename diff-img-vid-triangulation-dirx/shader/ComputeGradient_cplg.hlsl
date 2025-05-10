ByteAddressBuffer positions : register(t0);
ByteAddressBuffer indices : register(t1);
ByteAddressBuffer coefficients : register(t2);
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

//void integrate(float3 alpha, float3 alpha2, float3 beta, float3 beta2, float3 gamma, float3 gamma2, float a, float b, float c, float d, )

void gradient_rtt(float3 coeffsR, float3 coeffsG, float3 coeffsB, float2 A, float2 B, float2 C, inout float2 gradABC, inout float2 gradACB, inout float2 gradBCA)
{
    float3 alpha = float3(coeffsR.x, coeffsG.x, coeffsB.x);
    float3 beta = float3(coeffsR.y, coeffsG.y, coeffsB.y);
    float3 gamma = float3(coeffsR.z, coeffsG.z, coeffsB.z);
    
    float3 alpha2 = pow(abs(alpha), float3(2, 2, 2));
    float3 beta2 = pow(abs(beta), float3(2, 2, 2));
    float3 gamma2 = pow(abs(gamma), float3(2, 2, 2));
    
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

    float3 dims;
    image.GetDimensions(0, dims.x, dims.y, dims.z);
    
    int curX = floor(B.x);
    int curY = floor(B.y);
    int endX = floor(C.x);
    int endY = floor(C.y);
    
    float2 p = B;
    float2 q;
    
    float2 i0 = float2(0, 0), i1 = float2(0, 0);
    int intrsct;
    float a = 0, b = 0, c = 0, d = 1;
    float3 img_col, img_col2, nxt2, nxt3, nxt4, integral;
    bool4 last_pixel = bool4(false, false, false, false); //Bottom, Top, Left, Right
    
    last_pixel.x = B.y < C.y ? true : false;
    last_pixel.y = B.y > C.y ? true : false;
    last_pixel.z = B.x < C.x ? true : false; //test: (true, false, false, false)
    last_pixel.w = B.x > C.x ? true : false;

    int test = 0;
    while ( /*test < 5 &&*/(curX != endX || curY != endY))
    {
        img_col = image.Load(int3(min(dims.x - 1, curX), min(dims.y - 1, curY), 0)).rgb;
        img_col2 = pow(abs(img_col), float3(2, 2, 2));
        test++;
        //curX = endX;
        //curY = endY;
        if (!last_pixel.x)
        {
            intrsct = intersect_segments(B, bc, float2(curX, curY), float2(1, 0), i0, i1);
            if (intrsct == 1)
            {
                //continue;
                q = i0;
                b = length(p - B) / length_bc;
                c = length(p - C) / length_bc;
                
                //gradABC += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
                //float nxt2 = 0.5 * n_bc.x * (d * d - c * c) * (img_col.r * img_col.r - 2 * img_col.r * (coeffsR.x * B.x + coeffsR.y * B.y + coeffsR.z) + coeffsR.x * coeffsR.x * B.x * B.x + coeffsR.y * coeffsR.y * B.y * B.y + coeffsR.z * coeffsR.z);
                //float nxt3 = 1.0 / 3.0 * n_bc.x * (d * d * d - c * c * c) * (-2 * img_col.r * (coeffsR.x * bc.x + coeffsR.y * bc.y) + coeffsR.x * coeffsR.x * B.x * bc.x + coeffsR.y * coeffsR.y * B.y * bc.y);
                //float nxt4 = 0.25 * n_bc.x * (d * d * d * d - c * c * c * c) * (coeffsR.x * coeffsR.x * bc.x * bc.x + coeffsR.y * coeffsR.y * bc.y * bc.y);
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * bc.x + beta * bc.y) + alpha2 * 2 * B.x * bc.x + beta2 * 2 * B.y * bc.y + 2 * alpha * beta * (B.x * bc.y + B.y * bc.x) + 2 * alpha * gamma * bc.x + 2 * beta * gamma * bc.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * bc.x * bc.x + beta2 * bc.y * bc.y + 2 * alpha * beta * bc.x * bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                //gradACB += err * abs(length_bc * (0.5f * (d * d - c * c) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -bc.x + beta * -bc.y) + alpha2 * 2 * C.x * -bc.x + beta2 * 2 * C.y * -bc.y + 2 * alpha * beta * (C.x * -bc.y + C.y * -bc.x) + 2 * alpha * gamma * -bc.x + 2 * beta * gamma * -bc.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -bc.x * -bc.x + beta2 * -bc.y * -bc.y + 2 * alpha * beta * -bc.x * -bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
                
                p = q;
                a = b;
                d = c;
                curY -= 1;
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
            
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * bc.x + beta * bc.y) + alpha2 * 2 * B.x * bc.x + beta2 * 2 * B.y * bc.y + 2 * alpha * beta * (B.x * bc.y + B.y * bc.x) + 2 * alpha * gamma * bc.x + 2 * beta * gamma * bc.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * bc.x * bc.x + beta2 * bc.y * bc.y + 2 * alpha * beta * bc.x * bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
            
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -bc.x + beta * -bc.y) + alpha2 * 2 * C.x * -bc.x + beta2 * 2 * C.y * -bc.y + 2 * alpha * beta * (C.x * -bc.y + C.y * -bc.x) + 2 * alpha * gamma * -bc.x + 2 * beta * gamma * -bc.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -bc.x * -bc.x + beta2 * -bc.y * -bc.y + 2 * alpha * beta * -bc.x * -bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
            
                curX = (B.x < C.x) ? curX + 1 : curX - 1;
                //curX = endX;
                //curY = endY;
                continue;
            }
        }
        
        if (!last_pixel.z)
        {
            intrsct = intersect_segments(B, bc, float2(curX, curY), float2(0, 1), i0, i1);
            
            if (intrsct == 1)
            {
                //continue;
                q = i0;
                b = length(p - B) / length_bc;
                c = length(p - C) / length_bc;
                
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * bc.x + beta * bc.y) + alpha2 * 2 * B.x * bc.x + beta2 * 2 * B.y * bc.y + 2 * alpha * beta * (B.x * bc.y + B.y * bc.x) + 2 * alpha * gamma * bc.x + 2 * beta * gamma * bc.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * bc.x * bc.x + beta2 * bc.y * bc.y + 2 * alpha * beta * bc.x * bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
            
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -bc.x + beta * -bc.y) + alpha2 * 2 * C.x * -bc.x + beta2 * 2 * C.y * -bc.y + 2 * alpha * beta * (C.x * -bc.y + C.y * -bc.x) + 2 * alpha * gamma * -bc.x + 2 * beta * gamma * -bc.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -bc.x * -bc.x + beta2 * -bc.y * -bc.y + 2 * alpha * beta * -bc.x * -bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
                
                p = q;
                a = b;
                d = c;
                curX -= 1;
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
            
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * bc.x + beta * bc.y) + alpha2 * 2 * B.x * bc.x + beta2 * 2 * B.y * bc.y + 2 * alpha * beta * (B.x * bc.y + B.y * bc.x) + 2 * alpha * gamma * bc.x + 2 * beta * gamma * bc.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * bc.x * bc.x + beta2 * bc.y * bc.y + 2 * alpha * beta * bc.x * bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
            
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -bc.x + beta * -bc.y) + alpha2 * 2 * C.x * -bc.x + beta2 * 2 * C.y * -bc.y + 2 * alpha * beta * (C.x * -bc.y + C.y * -bc.x) + 2 * alpha * gamma * -bc.x + 2 * beta * gamma * -bc.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -bc.x * -bc.x + beta2 * -bc.y * -bc.y + 2 * alpha * beta * -bc.x * -bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
            
                curY = (B.y < C.y) ? curY + 1 : curY - 1;
                //curY = endY;
                //curX = endX;
                continue;
            }
        }
        
        if (!last_pixel.w)
        {
            intrsct = intersect_segments(B, bc, float2(curX + 1, curY), float2(0, 1), i0, i1);
            
            if (intrsct == 1)
            {
                //continue;
                q = i0;
                b = length(p - B) / length_bc;
                c = length(p - C) / length_bc;
                
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * bc.x + beta * bc.y) + alpha2 * 2 * B.x * bc.x + beta2 * 2 * B.y * bc.y + 2 * alpha * beta * (B.x * bc.y + B.y * bc.x) + 2 * alpha * gamma * bc.x + 2 * beta * gamma * bc.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * bc.x * bc.x + beta2 * bc.y * bc.y + 2 * alpha * beta * bc.x * bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
            
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -bc.x + beta * -bc.y) + alpha2 * 2 * C.x * -bc.x + beta2 * 2 * C.y * -bc.y + 2 * alpha * beta * (C.x * -bc.y + C.y * -bc.x) + 2 * alpha * gamma * -bc.x + 2 * beta * gamma * -bc.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -bc.x * -bc.x + beta2 * -bc.y * -bc.y + 2 * alpha * beta * -bc.x * -bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curX += 1;
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
            
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * bc.x + beta * bc.y) + alpha2 * 2 * B.x * bc.x + beta2 * 2 * B.y * bc.y + 2 * alpha * beta * (B.x * bc.y + B.y * bc.x) + 2 * alpha * gamma * bc.x + 2 * beta * gamma * bc.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * bc.x * bc.x + beta2 * bc.y * bc.y + 2 * alpha * beta * bc.x * bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
            
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -bc.x + beta * -bc.y) + alpha2 * 2 * C.x * -bc.x + beta2 * 2 * C.y * -bc.y + 2 * alpha * beta * (C.x * -bc.y + C.y * -bc.x) + 2 * alpha * gamma * -bc.x + 2 * beta * gamma * -bc.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -bc.x * -bc.x + beta2 * -bc.y * -bc.y + 2 * alpha * beta * -bc.x * -bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
            
                curY = (B.y < C.y) ? curY + 1 : curY - 1;
                //curY = endY;
                curX += 1;
                continue;
            }
        }
        
        if (!last_pixel.y)
        {
            intrsct = intersect_segments(B, bc, float2(curX, curY + 1), float2(1, 0), i0, i1);
            
            if (intrsct == 1)
            {
                //continue;
                q = i0;
                b = length(p - B) / length_bc;
                c = length(p - C) / length_bc;
                
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * bc.x + beta * bc.y) + alpha2 * 2 * B.x * bc.x + beta2 * 2 * B.y * bc.y + 2 * alpha * beta * (B.x * bc.y + B.y * bc.x) + 2 * alpha * gamma * bc.x + 2 * beta * gamma * bc.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * bc.x * bc.x + beta2 * bc.y * bc.y + 2 * alpha * beta * bc.x * bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
            
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -bc.x + beta * -bc.y) + alpha2 * 2 * C.x * -bc.x + beta2 * 2 * C.y * -bc.y + 2 * alpha * beta * (C.x * -bc.y + C.y * -bc.x) + 2 * alpha * gamma * -bc.x + 2 * beta * gamma * -bc.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -bc.x * -bc.x + beta2 * -bc.y * -bc.y + 2 * alpha * beta * -bc.x * -bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curY += 1;
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
            
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * bc.x + beta * bc.y) + alpha2 * 2 * B.x * bc.x + beta2 * 2 * B.y * bc.y + 2 * alpha * beta * (B.x * bc.y + B.y * bc.x) + 2 * alpha * gamma * bc.x + 2 * beta * gamma * bc.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * bc.x * bc.x + beta2 * bc.y * bc.y + 2 * alpha * beta * bc.x * bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradABC.y += integral.x + integral.y + integral.z;
            
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -bc.x + beta * -bc.y) + alpha2 * 2 * C.x * -bc.x + beta2 * 2 * C.y * -bc.y + 2 * alpha * beta * (C.x * -bc.y + C.y * -bc.x) + 2 * alpha * gamma * -bc.x + 2 * beta * gamma * -bc.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -bc.x * -bc.x + beta2 * -bc.y * -bc.y + 2 * alpha * beta * -bc.x * -bc.y);
                integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
                gradACB.y += integral.x + integral.y + integral.z;
            
                curX = (B.x < C.x) ? curX + 1 : curX - 1;
                //curX = endX;
                curY += 1;
                continue;
            }
        }
        break;
    }
    //if (curX < 0 || curY < 0)
      //  gradABC = 19283746;
    //TODO: p - C nach den Schleifen
    img_col = image.Load(int3(min(dims.x - 1, curX), min(dims.y - 1, curY), 0)).rgb;
    img_col2 = pow(abs(img_col), float3(2, 2, 2));
    
    a = max(a, b);
    b = 1.0f;
    d = min(c, d);
    c = 0.0f;
    
    nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
    nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * bc.x + beta * bc.y) + alpha2 * 2 * B.x * bc.x + beta2 * 2 * B.y * bc.y + 2 * alpha * beta * (B.x * bc.y + B.y * bc.x) + 2 * alpha * gamma * bc.x + 2 * beta * gamma * bc.y);
    nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * bc.x * bc.x + beta2 * bc.y * bc.y + 2 * alpha * beta * bc.x * bc.y);
    integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
    gradABC.x += integral.x + integral.y + integral.z;
    integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
    gradABC.y += integral.x + integral.y + integral.z;
            
    nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
    nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -bc.x + beta * -bc.y) + alpha2 * 2 * C.x * -bc.x + beta2 * 2 * C.y * -bc.y + 2 * alpha * beta * (C.x * -bc.y + C.y * -bc.x) + 2 * alpha * gamma * -bc.x + 2 * beta * gamma * -bc.y);
    nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -bc.x * -bc.x + beta2 * -bc.y * -bc.y + 2 * alpha * beta * -bc.x * -bc.y);
    integral = abs(length_bc * n_bc.x * (nxt2 + nxt3 + nxt4)) * f_right_x;
    gradACB.x += integral.x + integral.y + integral.z;
    integral = abs(length_bc * n_bc.y * (nxt2 + nxt3 + nxt4)) * f_right_y;
    gradACB.y += integral.x + integral.y + integral.z;
    
    //reset variables
    curX = floor(A.x);
    curY = floor(A.y);
    a = 0, b = 0, c = 0, d = 1;
    p = A;
    
    last_pixel.x = A.y < C.y ? true : false;
    last_pixel.y = A.y > C.y ? true : false;
    last_pixel.z = A.x < C.x ? true : false;
    last_pixel.w = A.x > C.x ? true : false;
    
    test = 0;
    
    while ( /*test < 50 && */(curX != endX || curY != endY))
    {
        img_col = image.Load(int3(min(dims.x - 1, curX), min(dims.y - 1, curY), 0)).rgb;
        img_col2 = pow(abs(img_col), float3(2, 2, 2));
        test++;
        if (!last_pixel.x)
        {
            intrsct = intersect_segments(A, ac, float2(curX, curY), float2(1, 0), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ac;
                c = length(p - C) / length_ac;
                
                //gradABC += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
                //gradBCA += err * abs(length_ac * (0.5f * (d * d - c * c) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ac.x + beta * ac.y) + alpha2 * 2 * A.x * ac.x + beta2 * 2 * A.y * ac.y + 2 * alpha * beta * (A.x * ac.y + A.y * ac.x) + 2 * alpha * gamma * ac.x + 2 * beta * gamma * ac.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ac.x * ac.x + beta2 * ac.y * ac.y + 2 * alpha * beta * ac.x * ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ac.x + beta * -ac.y) + alpha2 * 2 * C.x * -ac.x + beta2 * 2 * C.y * -ac.y + 2 * alpha * beta * (C.x * -ac.y + C.y * -ac.x) + 2 * alpha * gamma * -ac.x + 2 * beta * gamma * -ac.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ac.x * -ac.x + beta2 * -ac.y * -ac.y + 2 * alpha * beta * -ac.x * -ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
                //TODO: hier weitermachen (dy), dann Gradienten für interpolierte Pixel; außerdem die Berechnungen für ein einzelnes Dreieck testen
                p = q;
                a = b;
                d = c;
                curY -= 1;
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
            
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ac.x + beta * ac.y) + alpha2 * 2 * A.x * ac.x + beta2 * 2 * A.y * ac.y + 2 * alpha * beta * (A.x * ac.y + A.y * ac.x) + 2 * alpha * gamma * ac.x + 2 * beta * gamma * ac.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ac.x * ac.x + beta2 * ac.y * ac.y + 2 * alpha * beta * ac.x * ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ac.x + beta * -ac.y) + alpha2 * 2 * C.x * -ac.x + beta2 * 2 * C.y * -ac.y + 2 * alpha * beta * (C.x * -ac.y + C.y * -ac.x) + 2 * alpha * gamma * -ac.x + 2 * beta * gamma * -ac.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ac.x * -ac.x + beta2 * -ac.y * -ac.y + 2 * alpha * beta * -ac.x * -ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curX = A.x < C.x ? curX + 1 : curX - 1;
                continue;
            }
        }
        
        if (!last_pixel.z)
        {
            intrsct = intersect_segments(A, ac, float2(curX, curY), float2(0, 1), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ac;
                c = length(p - C) / length_ac;
                
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ac.x + beta * ac.y) + alpha2 * 2 * A.x * ac.x + beta2 * 2 * A.y * ac.y + 2 * alpha * beta * (A.x * ac.y + A.y * ac.x) + 2 * alpha * gamma * ac.x + 2 * beta * gamma * ac.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ac.x * ac.x + beta2 * ac.y * ac.y + 2 * alpha * beta * ac.x * ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ac.x + beta * -ac.y) + alpha2 * 2 * C.x * -ac.x + beta2 * 2 * C.y * -ac.y + 2 * alpha * beta * (C.x * -ac.y + C.y * -ac.x) + 2 * alpha * gamma * -ac.x + 2 * beta * gamma * -ac.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ac.x * -ac.x + beta2 * -ac.y * -ac.y + 2 * alpha * beta * -ac.x * -ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curX -= 1;
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
            
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ac.x + beta * ac.y) + alpha2 * 2 * A.x * ac.x + beta2 * 2 * A.y * ac.y + 2 * alpha * beta * (A.x * ac.y + A.y * ac.x) + 2 * alpha * gamma * ac.x + 2 * beta * gamma * ac.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ac.x * ac.x + beta2 * ac.y * ac.y + 2 * alpha * beta * ac.x * ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ac.x + beta * -ac.y) + alpha2 * 2 * C.x * -ac.x + beta2 * 2 * C.y * -ac.y + 2 * alpha * beta * (C.x * -ac.y + C.y * -ac.x) + 2 * alpha * gamma * -ac.x + 2 * beta * gamma * -ac.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ac.x * -ac.x + beta2 * -ac.y * -ac.y + 2 * alpha * beta * -ac.x * -ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curY = A.y < C.y ? curY + 1 : curY - 1;
                continue;
            }
        }
        
        if (!last_pixel.w)
        {
            intrsct = intersect_segments(A, ac, float2(curX + 1, curY), float2(0, 1), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ac;
                c = length(p - C) / length_ac;
                
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ac.x + beta * ac.y) + alpha2 * 2 * A.x * ac.x + beta2 * 2 * A.y * ac.y + 2 * alpha * beta * (A.x * ac.y + A.y * ac.x) + 2 * alpha * gamma * ac.x + 2 * beta * gamma * ac.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ac.x * ac.x + beta2 * ac.y * ac.y + 2 * alpha * beta * ac.x * ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ac.x + beta * -ac.y) + alpha2 * 2 * C.x * -ac.x + beta2 * 2 * C.y * -ac.y + 2 * alpha * beta * (C.x * -ac.y + C.y * -ac.x) + 2 * alpha * gamma * -ac.x + 2 * beta * gamma * -ac.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ac.x * -ac.x + beta2 * -ac.y * -ac.y + 2 * alpha * beta * -ac.x * -ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curX += 1;
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
            
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ac.x + beta * ac.y) + alpha2 * 2 * A.x * ac.x + beta2 * 2 * A.y * ac.y + 2 * alpha * beta * (A.x * ac.y + A.y * ac.x) + 2 * alpha * gamma * ac.x + 2 * beta * gamma * ac.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ac.x * ac.x + beta2 * ac.y * ac.y + 2 * alpha * beta * ac.x * ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ac.x + beta * -ac.y) + alpha2 * 2 * C.x * -ac.x + beta2 * 2 * C.y * -ac.y + 2 * alpha * beta * (C.x * -ac.y + C.y * -ac.x) + 2 * alpha * gamma * -ac.x + 2 * beta * gamma * -ac.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ac.x * -ac.x + beta2 * -ac.y * -ac.y + 2 * alpha * beta * -ac.x * -ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curY = A.y < C.y ? curY + 1 : curY - 1;
                curX += 1;
                continue;
            }
        }
        
        if (!last_pixel.y)
        {
            intrsct = intersect_segments(A, ac, float2(curX, curY + 1), float2(1, 0), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ac;
                c = length(p - C) / length_ac;
                
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ac.x + beta * ac.y) + alpha2 * 2 * A.x * ac.x + beta2 * 2 * A.y * ac.y + 2 * alpha * beta * (A.x * ac.y + A.y * ac.x) + 2 * alpha * gamma * ac.x + 2 * beta * gamma * ac.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ac.x * ac.x + beta2 * ac.y * ac.y + 2 * alpha * beta * ac.x * ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ac.x + beta * -ac.y) + alpha2 * 2 * C.x * -ac.x + beta2 * 2 * C.y * -ac.y + 2 * alpha * beta * (C.x * -ac.y + C.y * -ac.x) + 2 * alpha * gamma * -ac.x + 2 * beta * gamma * -ac.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ac.x * -ac.x + beta2 * -ac.y * -ac.y + 2 * alpha * beta * -ac.x * -ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curY += 1;
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
            
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ac.x + beta * ac.y) + alpha2 * 2 * A.x * ac.x + beta2 * 2 * A.y * ac.y + 2 * alpha * beta * (A.x * ac.y + A.y * ac.x) + 2 * alpha * gamma * ac.x + 2 * beta * gamma * ac.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ac.x * ac.x + beta2 * ac.y * ac.y + 2 * alpha * beta * ac.x * ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradABC.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradABC.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ac.x + beta * -ac.y) + alpha2 * 2 * C.x * -ac.x + beta2 * 2 * C.y * -ac.y + 2 * alpha * beta * (C.x * -ac.y + C.y * -ac.x) + 2 * alpha * gamma * -ac.x + 2 * beta * gamma * -ac.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ac.x * -ac.x + beta2 * -ac.y * -ac.y + 2 * alpha * beta * -ac.x * -ac.y);
                integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curX = A.x < C.x ? curX + 1 : curX - 1;
                curY += 1;
                continue;
            }
        }
        break;
    }
    //if (curX < 0 || curY < 0)
      //  gradABC = 19283746;
    img_col = image.Load(int3(min(dims.x - 1, curX), min(dims.y - 1, curY), 0)).rgb;
    img_col2 = pow(abs(img_col), float3(2, 2, 2));
    a = max(a, b);
    b = 1.0f;
    d = min(c, d);
    c = 0.0f;
    nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
    nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ac.x + beta * ac.y) + alpha2 * 2 * A.x * ac.x + beta2 * 2 * A.y * ac.y + 2 * alpha * beta * (A.x * ac.y + A.y * ac.x) + 2 * alpha * gamma * ac.x + 2 * beta * gamma * ac.y);
    nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ac.x * ac.x + beta2 * ac.y * ac.y + 2 * alpha * beta * ac.x * ac.y);
    integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
    gradABC.x += integral.x + integral.y + integral.z;
    integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
    gradABC.y += integral.x + integral.y + integral.z;
                
    nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * C.x + beta * C.y + gamma) + alpha2 * C.x * C.x + beta2 * C.y * C.y + gamma2 + 2 * alpha * beta * C.x * C.y + 2 * alpha * C.x * gamma + 2 * beta * C.y * gamma);
    nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ac.x + beta * -ac.y) + alpha2 * 2 * C.x * -ac.x + beta2 * 2 * C.y * -ac.y + 2 * alpha * beta * (C.x * -ac.y + C.y * -ac.x) + 2 * alpha * gamma * -ac.x + 2 * beta * gamma * -ac.y);
    nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ac.x * -ac.x + beta2 * -ac.y * -ac.y + 2 * alpha * beta * -ac.x * -ac.y);
    integral = abs(length_ac * n_ac.x * (nxt2 + nxt3 + nxt4)) * f_left_x;
    gradBCA.x += integral.x + integral.y + integral.z;
    integral = abs(length_ac * n_ac.y * (nxt2 + nxt3 + nxt4)) * f_left_y;
    gradBCA.y += integral.x + integral.y + integral.z;
    
    curX = floor(A.x);
    curY = floor(A.y);
    endX = floor(B.x);
    endY = floor(B.y);
    a = 0, b = 0, c = 0, d = 1;
    p = A;
    
    last_pixel.x = A.y < B.y ? true : false;
    last_pixel.y = A.y > B.y ? true : false;
    last_pixel.z = A.x < B.x ? true : false;
    last_pixel.w = A.x > B.x ? true : false;
    
    test = 0;
    
    while ( /*test < 50 &&*/(curX != endX || curY != endY))
    {
        img_col = image.Load(int3(min(dims.x - 1, curX), min(dims.y - 1, curY), 0)).rgb;
        img_col2 = pow(abs(img_col), float3(2, 2, 2));
        test++;
        if (!last_pixel.x)
        {
            intrsct = intersect_segments(A, ab, float2(curX, curY), float2(1, 0), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ab;
                c = length(p - B) / length_ab;
                
                //gradACB += err * abs(length_ab * (0.5f * (b * b - a * a) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
                //gradBCA += err * abs(length_ab * (0.5f * (d * d - c * c) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
            
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ab.x + beta * ab.y) + alpha2 * 2 * A.x * ab.x + beta2 * 2 * A.y * ab.y + 2 * alpha * beta * (A.x * ab.y + A.y * ab.x) + 2 * alpha * gamma * ab.x + 2 * beta * gamma * ab.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ab.x * ab.x + beta2 * ab.y * ab.y + 2 * alpha * beta * ab.x * ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ab.x + beta * -ab.y) + alpha2 * 2 * B.x * -ab.x + beta2 * 2 * B.y * -ab.y + 2 * alpha * beta * (B.x * -ab.y + B.y * -ab.x) + 2 * alpha * gamma * -ab.x + 2 * beta * gamma * -ab.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ab.x * -ab.x + beta2 * -ab.y * -ab.y + 2 * alpha * beta * -ab.x * -ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
                
                p = q;
                a = b;
                d = c;
                curY -= 1;
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
            
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ab.x + beta * ab.y) + alpha2 * 2 * A.x * ab.x + beta2 * 2 * A.y * ab.y + 2 * alpha * beta * (A.x * ab.y + A.y * ab.x) + 2 * alpha * gamma * ab.x + 2 * beta * gamma * ab.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ab.x * ab.x + beta2 * ab.y * ab.y + 2 * alpha * beta * ab.x * ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ab.x + beta * -ab.y) + alpha2 * 2 * B.x * -ab.x + beta2 * 2 * B.y * -ab.y + 2 * alpha * beta * (B.x * -ab.y + B.y * -ab.x) + 2 * alpha * gamma * -ab.x + 2 * beta * gamma * -ab.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ab.x * -ab.x + beta2 * -ab.y * -ab.y + 2 * alpha * beta * -ab.x * -ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curX = A.x < B.x ? curX + 1 : curX - 1;
                continue;
            }
        }
        
        if (!last_pixel.z)
        {
            intrsct = intersect_segments(A, ab, float2(curX, curY), float2(0, 1), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ab;
                c = length(p - B) / length_ab;
                
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ab.x + beta * ab.y) + alpha2 * 2 * A.x * ab.x + beta2 * 2 * A.y * ab.y + 2 * alpha * beta * (A.x * ab.y + A.y * ab.x) + 2 * alpha * gamma * ab.x + 2 * beta * gamma * ab.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ab.x * ab.x + beta2 * ab.y * ab.y + 2 * alpha * beta * ab.x * ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ab.x + beta * -ab.y) + alpha2 * 2 * B.x * -ab.x + beta2 * 2 * B.y * -ab.y + 2 * alpha * beta * (B.x * -ab.y + B.y * -ab.x) + 2 * alpha * gamma * -ab.x + 2 * beta * gamma * -ab.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ab.x * -ab.x + beta2 * -ab.y * -ab.y + 2 * alpha * beta * -ab.x * -ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curX -= 1;
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
            
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ab.x + beta * ab.y) + alpha2 * 2 * A.x * ab.x + beta2 * 2 * A.y * ab.y + 2 * alpha * beta * (A.x * ab.y + A.y * ab.x) + 2 * alpha * gamma * ab.x + 2 * beta * gamma * ab.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ab.x * ab.x + beta2 * ab.y * ab.y + 2 * alpha * beta * ab.x * ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ab.x + beta * -ab.y) + alpha2 * 2 * B.x * -ab.x + beta2 * 2 * B.y * -ab.y + 2 * alpha * beta * (B.x * -ab.y + B.y * -ab.x) + 2 * alpha * gamma * -ab.x + 2 * beta * gamma * -ab.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ab.x * -ab.x + beta2 * -ab.y * -ab.y + 2 * alpha * beta * -ab.x * -ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curY = A.y < B.y ? curY + 1 : curY - 1;
                continue;
            }
        }
        
        if (!last_pixel.w)
        {
            intrsct = intersect_segments(A, ab, float2(curX + 1, curY), float2(0, 1), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ab;
                c = length(p - B) / length_ab;
                
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ab.x + beta * ab.y) + alpha2 * 2 * A.x * ab.x + beta2 * 2 * A.y * ab.y + 2 * alpha * beta * (A.x * ab.y + A.y * ab.x) + 2 * alpha * gamma * ab.x + 2 * beta * gamma * ab.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ab.x * ab.x + beta2 * ab.y * ab.y + 2 * alpha * beta * ab.x * ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ab.x + beta * -ab.y) + alpha2 * 2 * B.x * -ab.x + beta2 * 2 * B.y * -ab.y + 2 * alpha * beta * (B.x * -ab.y + B.y * -ab.x) + 2 * alpha * gamma * -ab.x + 2 * beta * gamma * -ab.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ab.x * -ab.x + beta2 * -ab.y * -ab.y + 2 * alpha * beta * -ab.x * -ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curX += 1;
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
            
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ab.x + beta * ab.y) + alpha2 * 2 * A.x * ab.x + beta2 * 2 * A.y * ab.y + 2 * alpha * beta * (A.x * ab.y + A.y * ab.x) + 2 * alpha * gamma * ab.x + 2 * beta * gamma * ab.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ab.x * ab.x + beta2 * ab.y * ab.y + 2 * alpha * beta * ab.x * ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ab.x + beta * -ab.y) + alpha2 * 2 * B.x * -ab.x + beta2 * 2 * B.y * -ab.y + 2 * alpha * beta * (B.x * -ab.y + B.y * -ab.x) + 2 * alpha * gamma * -ab.x + 2 * beta * gamma * -ab.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ab.x * -ab.x + beta2 * -ab.y * -ab.y + 2 * alpha * beta * -ab.x * -ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curY = A.y < B.y ? curY + 1 : curY - 1;
                curX += 1;
                continue;
            }
        }
        
        if (!last_pixel.y)
        {
            intrsct = intersect_segments(A, ab, float2(curX, curY + 1), float2(1, 0), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ab;
                c = length(p - B) / length_ab;
                
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ab.x + beta * ab.y) + alpha2 * 2 * A.x * ab.x + beta2 * 2 * A.y * ab.y + 2 * alpha * beta * (A.x * ab.y + A.y * ab.x) + 2 * alpha * gamma * ab.x + 2 * beta * gamma * ab.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ab.x * ab.x + beta2 * ab.y * ab.y + 2 * alpha * beta * ab.x * ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ab.x + beta * -ab.y) + alpha2 * 2 * B.x * -ab.x + beta2 * 2 * B.y * -ab.y + 2 * alpha * beta * (B.x * -ab.y + B.y * -ab.x) + 2 * alpha * gamma * -ab.x + 2 * beta * gamma * -ab.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ab.x * -ab.x + beta2 * -ab.y * -ab.y + 2 * alpha * beta * -ab.x * -ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                p = q;
                a = b;
                d = c;
                curY += 1;
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
            
                nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
                nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ab.x + beta * ab.y) + alpha2 * 2 * A.x * ab.x + beta2 * 2 * A.y * ab.y + 2 * alpha * beta * (A.x * ab.y + A.y * ab.x) + 2 * alpha * gamma * ab.x + 2 * beta * gamma * ab.y);
                nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ab.x * ab.x + beta2 * ab.y * ab.y + 2 * alpha * beta * ab.x * ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradACB.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradACB.y += integral.x + integral.y + integral.z;
                
                nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
                nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ab.x + beta * -ab.y) + alpha2 * 2 * B.x * -ab.x + beta2 * 2 * B.y * -ab.y + 2 * alpha * beta * (B.x * -ab.y + B.y * -ab.x) + 2 * alpha * gamma * -ab.x + 2 * beta * gamma * -ab.y);
                nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ab.x * -ab.x + beta2 * -ab.y * -ab.y + 2 * alpha * beta * -ab.x * -ab.y);
                integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
                gradBCA.x += integral.x + integral.y + integral.z;
                integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
                gradBCA.y += integral.x + integral.y + integral.z;
            
                curX = A.x < B.x ? curX + 1 : curX - 1;
                curY += 1;
                continue;
            }
        }
        break;
    }
    //if (curX < 0 || curY < 0)
      //  gradABC = 19283746;
    img_col = image.Load(int3(min(dims.x - 1, curX), min(dims.y - 1, curY), 0)).rgb;
    img_col2 = pow(abs(img_col), float3(2, 2, 2));
    a = max(a, b);
    b = 1.0f;
    d = min(c, d);
    c = 0.0f;
    nxt2 = 0.5 * (b * b - a * a) * (img_col2 - 2 * img_col * (alpha * A.x + beta * A.y + gamma) + alpha2 * A.x * A.x + beta2 * A.y * A.y + gamma2 + 2 * alpha * beta * A.x * A.y + 2 * alpha * A.x * gamma + 2 * beta * A.y * gamma);
    nxt3 = 1.0 / 3.0 * (b * b * b - a * a * a) * (-2 * img_col * (alpha * ab.x + beta * ab.y) + alpha2 * 2 * A.x * ab.x + beta2 * 2 * A.y * ab.y + 2 * alpha * beta * (A.x * ab.y + A.y * ab.x) + 2 * alpha * gamma * ab.x + 2 * beta * gamma * ab.y);
    nxt4 = 0.25 * (b * b * b * b - a * a * a * a) * (alpha2 * ab.x * ab.x + beta2 * ab.y * ab.y + 2 * alpha * beta * ab.x * ab.y);
    integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
    gradACB.x += integral.x + integral.y + integral.z;
    integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
    gradACB.y += integral.x + integral.y + integral.z;
                
    nxt2 = 0.5 * (d * d - c * c) * (img_col2 - 2 * img_col * (alpha * B.x + beta * B.y + gamma) + alpha2 * B.x * B.x + beta2 * B.y * B.y + gamma2 + 2 * alpha * beta * B.x * B.y + 2 * alpha * B.x * gamma + 2 * beta * B.y * gamma);
    nxt3 = 1.0 / 3.0 * (d * d * d - c * c * c) * (-2 * img_col * (alpha * -ab.x + beta * -ab.y) + alpha2 * 2 * B.x * -ab.x + beta2 * 2 * B.y * -ab.y + 2 * alpha * beta * (B.x * -ab.y + B.y * -ab.x) + 2 * alpha * gamma * -ab.x + 2 * beta * gamma * -ab.y);
    nxt4 = 0.25 * (d * d * d * d - c * c * c * c) * (alpha2 * -ab.x * -ab.x + beta2 * -ab.y * -ab.y + 2 * alpha * beta * -ab.x * -ab.y);
    integral = abs(length_ab * n_ab.x * (nxt2 + nxt3 + nxt4)) * f_ab_x;
    gradBCA.x += integral.x + integral.y + integral.z;
    integral = abs(length_ab * n_ab.y * (nxt2 + nxt3 + nxt4)) * f_ab_y;
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
    float3 cR = float3(1.74491e-07, -4.89523e-09, 0.133323);
    float3 cG = float3(2.08421e-06, -4.80801e-08, 0.693996);
    float3 cB = float3(3.87866e-07, -1.60368e-08, 0.298017);
    gradient_rtt(cR, cG, cB, float2(0, 0), float2(78.0455, 0), float2(78.0455, 43.7727), grABC, grACB, grBCA);
    //gradient_rtt(tri_col, A, B, C, 1.0f, 0.0f, grABC, grACB, grBCA);
    //gradient_rtt(tri_col, A, B, C, 0.0f, 1.0f, grABC, grACB, grBCA);
    
    if (grABC.y != 0)//grABC.x != 0.0f)
    {
        return grBCA.x;
    }
    return grBCA.x;
}

[numthreads(512, 1, 1)]
void main(uint DTid : SV_DispatchThreadID)
{
    /*float tst = test();
    if (abs(tst) >= 0.000001)
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
    
    float3 coeffsR = asfloat(coefficients.Load3(DTid * 36));
    float3 coeffsG = asfloat(coefficients.Load3(DTid * 36 + 12));
    float3 coeffsB = asfloat(coefficients.Load3(DTid * 36 + 24));
    
    float2 grABC = float2(0.0f, 0.0f);
    float2 grACB = float2(0.0f, 0.0f);
    float2 grBCA = float2(0.0f, 0.0f);
    
    gradient_rtt(coeffsR, coeffsG, coeffsB, A, B, C, grABC, grACB, grBCA);
    //gradient_rtt(tri_col, A, B, C, 0.0f, 1.0f, grABC, grACB, grBCA);

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