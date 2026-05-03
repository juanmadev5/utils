# ASP.NET Core — JWT Authentication

## Paquetes NuGet necesarios

```
BCrypt.Net-Next
Microsoft.AspNetCore.Authentication.JwtBearer
```

---

## 1. appsettings.json

```json
"JwtSettings": {
  "Secret": "CHANGE_THIS_SECRET_KEY_MIN_32_CHARS!!",
  "Issuer": "your-api",
  "Audience": "your-api-clients",
  "ExpiryMinutes": 60
},
"BcryptSettings": {
  "WorkFactor": 12
}
```

---

## 2. Entidad User

```csharp
public class User
{
    public int Id { get; set; }
    public required string Email { get; set; }
    public required string PasswordHash { get; set; }
}
```

---

## 3. DbContext

Agregar dentro de `AppDbContext`:

```csharp
public DbSet<User> Users { get; set; }

protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    modelBuilder.Entity<User>()
        .HasIndex(u => u.Email)
        .IsUnique();
}
```

---

## 4. DTOs

```csharp
public record LoginDto(
    [Required][EmailAddress] string Email,
    [Required] string Password
);

public record RegisterDto(
    [Required][EmailAddress] string Email,
    [Required][MinLength(6)] string Password
);

public record AuthResponseDto(string Token, string Email);
```

---

## 5. Interfaz e implementación del repositorio

```csharp
public interface IUserRepository
{
    Task<User?> GetByEmail(string email);
    Task<bool> Create(User user);
}
```

```csharp
public class UserRepository(AppDbContext context) : IUserRepository
{
    private readonly AppDbContext _context = context;

    public async Task<User?> GetByEmail(string email)
        => await _context.Users.FirstOrDefaultAsync(u => u.Email == email);

    public async Task<bool> Create(User user)
    {
        try
        {
            await _context.Users.AddAsync(user);
            await _context.SaveChangesAsync();
            return true;
        }
        catch (Exception)
        {
            return false;
        }
    }
}
```

---

## 6. Interfaz e implementación del servicio

```csharp
public interface IAuthService
{
    Task<ActionResponse<AuthResponseDto>> Register(RegisterDto dto);
    Task<ActionResponse<AuthResponseDto>> Login(LoginDto dto);
}
```

```csharp
public class AuthService(IUserRepository repository, IConfiguration configuration) : IAuthService
{
    private readonly IUserRepository _repository = repository;
    private readonly IConfiguration _configuration = configuration;

    public async Task<ActionResponse<AuthResponseDto>> Register(RegisterDto dto)
    {
        var existing = await _repository.GetByEmail(dto.Email);
        if (existing != null)
            return new ActionResponse<AuthResponseDto>(null, "Email already registered.", Status.FAILED);

        int workFactor = _configuration.GetValue<int>("BcryptSettings:WorkFactor", 12);

        var user = new User
        {
            Email = dto.Email,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(dto.Password, workFactor)
        };

        bool success = await _repository.Create(user);
        if (!success)
            return new ActionResponse<AuthResponseDto>(null, "Could not register user.", Status.FAILED);

        return new ActionResponse<AuthResponseDto>(
            new AuthResponseDto(GenerateToken(user), user.Email),
            "User registered.",
            Status.SUCCESS
        );
    }

    public async Task<ActionResponse<AuthResponseDto>> Login(LoginDto dto)
    {
        var user = await _repository.GetByEmail(dto.Email);

        if (user == null || !BCrypt.Net.BCrypt.Verify(dto.Password, user.PasswordHash))
            return new ActionResponse<AuthResponseDto>(null, "Invalid credentials.", Status.FAILED);

        return new ActionResponse<AuthResponseDto>(
            new AuthResponseDto(GenerateToken(user), user.Email),
            "Login successful.",
            Status.SUCCESS
        );
    }

    private string GenerateToken(User user)
    {
        var jwtSettings = _configuration.GetSection("JwtSettings");
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSettings["Secret"]!));

        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new Claim(JwtRegisteredClaimNames.Email, user.Email),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };

        var token = new JwtSecurityToken(
            issuer: jwtSettings["Issuer"],
            audience: jwtSettings["Audience"],
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(jwtSettings.GetValue<int>("ExpiryMinutes", 60)),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256)
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
```

---

## 7. Controller de autenticación

```csharp
[Route("api/[controller]")]
[ApiController]
public class AuthController(IAuthService service) : ControllerBase
{
    private readonly IAuthService _service = service;

    [HttpPost("register")]
    public async Task<IActionResult> Register(RegisterDto dto)
    {
        var result = await _service.Register(dto);
        return result.Status == Status.SUCCESS ? Ok(result) : BadRequest(result);
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login(LoginDto dto)
    {
        var result = await _service.Login(dto);
        return result.Status == Status.SUCCESS ? Ok(result) : Unauthorized(result);
    }
}
```

---

## 8. Proteger un controller con [Authorize]

```csharp
[Authorize]
[Route("api/[controller]")]
[ApiController]
public class SomeController : ControllerBase
{
    // Extrae el Id del usuario autenticado desde los claims del JWT
    private int GetUserId() =>
        int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        int userId = GetUserId();
        // filtrar datos por userId...
        return Ok();
    }
}
```

---

## 9. Program.cs

```csharp
// Registrar dependencias
builder.Services.AddScoped<IUserRepository, UserRepository>();
builder.Services.AddScoped<IAuthService, AuthService>();

// Configurar JWT
var jwtSettings = builder.Configuration.GetSection("JwtSettings");

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwtSettings["Issuer"],
            ValidAudience = jwtSettings["Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(jwtSettings["Secret"]!)
            )
        };
    });
```

```csharp
// Pipeline — el orden importa
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
```

---

## Flujo completo

```
POST /api/auth/register  { email, password }
  → hashea password con BCrypt
  → guarda User en BD
  → devuelve JWT + email

POST /api/auth/login  { email, password }
  → busca User por email
  → verifica password con BCrypt
  → devuelve JWT + email

Requests protegidos:
  Authorization: Bearer <token>
  → middleware valida el JWT automáticamente
  → GetUserId() lee el claim Sub del token
```
