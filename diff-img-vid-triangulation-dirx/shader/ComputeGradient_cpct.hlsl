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

void gradient_rtt(float3 tri_color, float2 A, float2 B, float2 C, float dx, float dy, inout float gradABC, inout float gradACB, inout float gradBCA) 
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
    
    int f_right = 1;
    float2 n = -normal_out(bc, ba);
    if (dot(n, float2(dx, dy)) > 0)
        f_right = -1;
    
    int f_left = 1;
    n = -normal_out(ac, -ba);
    if (dot(n, float2(dx, dy)) > 0)
        f_left = -1;

    int f_ab = 1;
    n = -normal_out(ab, ac);
    if (dot(n, float2(dx, dy)) > 0)
        f_ab = -1;
    
    gradABC = 0.0f;
    gradACB = 0.0f;                                                             //TODO: zweite Schleife ergänzen, dritte Schleife, UpdatePositionsRTT.hlsl
    gradBCA = 0.0f;

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
    float a = 0, b = 0, c = 0, d = 1, err = 0.0f;
    float3 img_col, err3;
    bool4 last_pixel = bool4(false, false, false, false); //Bottom, Top, Left, Right
    
    last_pixel.x = B.y < C.y ? true : false;
    last_pixel.y = B.y > C.y ? true : false;
    last_pixel.z = B.x < C.x ? true : false; //test: (true, false, false, false)
    last_pixel.w = B.x > C.x ? true : false;
        
    /*if (B.y <= C.y)
    {
        last_pixel.x = true;
        last_pixel.y = false;
    }
    else
    {
        last_pixel.x = false;
        last_pixel.y = true;
    }
    if (B.x <= C.x)
    {
        last_pixel.z = true;
        last_pixel.w = false;
    }
    else
    {
        last_pixel.z = false;
        last_pixel.w = true;
    }*/
    //TODO: test ohne abs bei gradients
    int test = 0;
    while (/*test < 5 &&*/ (curX != endX || curY != endY))
    {
        img_col = image.Load(int3(min(dims.x - 1, curX), min(dims.y - 1, curY), 0)).rgb;
        err3 = pow(abs((img_col - tri_color)), 2);
        err = err3.x + err3.y + err3.z;
        test++;
        //curX = endX;
        //curY = endY;
        if (!last_pixel.x)
        {
            intrsct = intersect_segments(B, bc, float2(curX, curY), float2(1, 0), i0, i1);
            /*if (intrsct == 3)
            {
                curX = endX;
                curY = endY;
                continue;
            }*/
            if (intrsct == 1)
            {
                //continue;
                q = i0;
                b = length(p - B) / length_bc;
                c = length(p - C) / length_bc;
                
                gradABC += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
                gradACB += err * abs(length_bc * (0.5f * (d * d - c * c) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
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
            
                gradABC += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
                gradACB += err * abs(length_bc * (0.5f * (d * d - c * c) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
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
                
                gradABC += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
                gradACB += err * abs(length_bc * (0.5f * (d * d - c * c) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
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
            
                gradABC += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
                gradACB += err * abs(length_bc * (0.5f * (d * d - c * c) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
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
                
                gradABC += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
                gradACB += err * abs(length_bc * (0.5f * (d * d - c * c) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
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
            
                gradABC += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
                gradACB += err * abs(length_bc * (0.5f * (d * d - c * c) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
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
                
                gradABC += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
                gradACB += err * abs(length_bc * (0.5f * (d * d - c * c) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
                p = q;
                a = b;
                d = c;
                curY += 1;
                last_pixel.x = true;//bool4(true, false, false, false);
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
            
                gradABC += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
                gradACB += err * abs(length_bc * (0.5f * (d * d - c * c) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
            
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
    err3 = pow(abs((img_col - tri_color)), 2);
    err = err3.x + err3.y + err3.z;
    
    a = max(a, b);
    b = 1.0f;
    d = min(c, d);
    c = 0.0f;
    
    gradABC += err * abs(length_bc * (0.5f * (b * b - a * a) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
    gradACB += err * abs(length_bc * (0.5f * (d * d - c * c) * (n_bc.x * dx + n_bc.y * dy))) * f_right;
    
    //reset variables
    curX = floor(A.x);
    curY = floor(A.y);
    a = 0, b = 0, c = 0, d = 1;
    p = A;
    
    last_pixel.x = A.y < C.y ? true : false;
    last_pixel.y = A.y > C.y ? true : false;
    last_pixel.z = A.x < C.x ? true : false;
    last_pixel.w = A.x > C.x ? true : false;
    
    /*if (A.y <= C.y)
    {
        last_pixel.x = true;
        last_pixel.y = false;
    }
    else
    {
        last_pixel.x = false;
        last_pixel.y = true;
    }
    if (A.x <= C.x)
    {
        last_pixel.z = true;
        last_pixel.w = false;
    }
    else
    {
        last_pixel.z = false;
        last_pixel.w = true;
    }*/
    
    test = 0;
    
    while (/*test < 50 && */(curX != endX || curY != endY))
    {
        img_col = image.Load(int3(min(dims.x - 1, curX), min(dims.y - 1, curY), 0)).rgb;
        err3 = pow(abs((img_col - tri_color)), 2);
        err = err3.x + err3.y + err3.z;
        test++;
        if (!last_pixel.x)
        {
            intrsct = intersect_segments(A, ac, float2(curX, curY), float2(1, 0), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ac;
                c = length(p - C) / length_ac;
                
                gradABC += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
                gradBCA += err * abs(length_ac * (0.5f * (d * d - c * c) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
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
            
                gradABC += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
                gradBCA += err * abs(length_ac * (0.5f * (d * d - c * c) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
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
                
                gradABC += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
                gradBCA += err * abs(length_ac * (0.5f * (d * d - c * c) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
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
            
                gradABC += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
                gradBCA += err * abs(length_ac * (0.5f * (d * d - c * c) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
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
                
                gradABC += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
                gradBCA += err * abs(length_ac * (0.5f * (d * d - c * c) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
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
            
                gradABC += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
                gradBCA += err * abs(length_ac * (0.5f * (d * d - c * c) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
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
                
                gradABC += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
                gradBCA += err * abs(length_ac * (0.5f * (d * d - c * c) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
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
            
                gradABC += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
                gradBCA += err * abs(length_ac * (0.5f * (d * d - c * c) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
            
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
    err3 = pow(abs((img_col - tri_color)), 2);
    err = err3.x + err3.y + err3.z;
    a = max(a, b);
    b = 1.0f;
    d = min(c, d);
    c = 0.0f;
    gradABC += err * abs(length_ac * (0.5f * (b * b - a * a) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
    gradBCA += err * abs(length_ac * (0.5f * (d * d - c * c) * (n_ac.x * dx + n_ac.y * dy))) * f_left;
    
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
    
    /*if (A.y <= B.y)
    {
        last_pixel.x = true;
        last_pixel.y = false;
    }
    else
    {
        last_pixel.x = false;
        last_pixel.y = true;
    }
    if (A.x <= B.x)
    {
        last_pixel.z = true;
        last_pixel.w = false;
    }
    else
    {
        last_pixel.z = false;
        last_pixel.w = true;
    }*/
    
    test = 0;
    
    while (/*test < 50 &&*/ (curX != endX || curY != endY))
    {
        img_col = image.Load(int3(min(dims.x - 1, curX), min(dims.y - 1, curY), 0)).rgb;
        err3 = pow(abs((img_col - tri_color)), 2);
        err = err3.x + err3.y + err3.z;
        test++;
        if (!last_pixel.x)
        {
            intrsct = intersect_segments(A, ab, float2(curX, curY), float2(1, 0), i0, i1);
            if (intrsct == 1)
            {
                q = i0;
                b = length(p - A) / length_ab;
                c = length(p - B) / length_ab;
                
                gradACB += err * abs(length_ab * (0.5f * (b * b - a * a) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
                gradBCA += err * abs(length_ab * (0.5f * (d * d - c * c) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
            
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
            
                gradACB += err * abs(length_ab * (0.5f * (b * b - a * a) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
                gradBCA += err * abs(length_ab * (0.5f * (d * d - c * c) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
            
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
                
                gradACB += err * abs(length_ab * (0.5f * (b * b - a * a) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
                gradBCA += err * abs(length_ab * (0.5f * (d * d - c * c) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
            
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
            
                gradACB += err * abs(length_ab * (0.5f * (b * b - a * a) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
                gradBCA += err * abs(length_ab * (0.5f * (d * d - c * c) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
            
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
                
                gradACB += err * abs(length_ab * (0.5f * (b * b - a * a) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
                gradBCA += err * abs(length_ab * (0.5f * (d * d - c * c) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
            
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
            
                gradACB += err * abs(length_ab * (0.5f * (b * b - a * a) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
                gradBCA += err * abs(length_ab * (0.5f * (d * d - c * c) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
            
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
                
                gradACB += err * abs(length_ab * (0.5f * (b * b - a * a) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
                gradBCA += err * abs(length_ab * (0.5f * (d * d - c * c) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
            
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
            
                gradACB += err * abs(length_ab * (0.5f * (b * b - a * a) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
                gradBCA += err * abs(length_ab * (0.5f * (d * d - c * c) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
            
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
    err3 = pow(abs((img_col - tri_color)), 2);
    err = err3.x + err3.y + err3.z;
    a = max(a, b);
    b = 1.0f;
    d = min(c, d);
    c = 0.0f;
    gradACB += err * abs(length_ab * (0.5f * (b * b - a * a) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
    gradBCA += err * abs(length_ab * (0.5f * (d * d - c * c) * (n_ab.x * dx + n_ab.y * dy))) * f_ab;
}

float test()
{
    /*float3 tri_col = float3(254.0f / 255.0f, 0, 0);
    float2 A = float2(0.0f, 0.0f);
    float2 B = float2(3.0f, 3.0f);
    loat2 C = float2(0.0f, 3.0f);*/
    float3 tri_col = float3(254.0f / 255.0f, 0, 0);
    float2 A = float2(797.0f, 500.0f);
    float2 B = float2(800.0f, 500.0f);
    float2 C = float2(800.0f, 503.0f);
    
    float2 grABC = float2(0.0f, 0.0f);
    float2 grACB = float2(0.0f, 0.0f);
    float2 grBCA = float2(0.0f, 0.0f);
    float grabcx = 0.0f;
    gradient_rtt(tri_col, A, B, C, 1.0f, 0.0f, grABC.x, grACB.x, grBCA.x);
    gradient_rtt(tri_col, A, B, C, 0.0f, 1.0f, grABC.y, grACB.y, grBCA.y);
    
    if (grABC.y != 0)//grABC.x != 0.0f)
    {
        return grBCA.x;
    }
    return grBCA.x;
}

[numthreads(512, 1, 1)]
void main( uint DTid : SV_DispatchThreadID )
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
    
    gradient_rtt(tri_col, A, B, C, 1.0f, 0.0f, grABC.x, grACB.x, grBCA.x);
    gradient_rtt(tri_col, A, B, C, 0.0f, 1.0f, grABC.y, grACB.y, grBCA.y);

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